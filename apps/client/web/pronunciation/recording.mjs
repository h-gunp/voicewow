// Bound browser inference memory; the native Android engine keeps its 20-second limit.
const MAX_SECONDS = 10;
const DELIVERY_TIMEOUT_MS = 3000;
const FINAL_TIMEOUT_MS = 1000;
const START_TIMEOUT_MS = 15000;
const aborted = () => new DOMException('Recording cancelled', 'AbortError');
const active = session => ['starting', 'recording', 'stopping'].includes(session.phase);
const stopTracks = stream => { for (const track of stream?.getTracks() || []) track.stop(); };

/** A user gesture must call start(). stop() waits for the final PCM acknowledgment.
 * onLimit fires after automatic stop begins; stop() then returns the same result.
 * Startup errors reject start(); later failures also call onError once.
 * PCM retains the AudioContext rate. Browser processing constraints are best effort.
 */
export function createRecorder({ onLimit = () => {}, onError = () => {} } = {}) {
  let current;

  function cleanup(session) {
    if (session.cleaned) return session.cleanup;
    session.cleaned = true;
    for (const timer of ['startupTimer', 'deliveryTimer', 'limitTimer', 'finalTimer']) clearTimeout(session[timer]);
    for (const track of session.stream?.getAudioTracks() || []) track.removeEventListener('ended', session.onEnded);
    stopTracks(session.stream);
    if (session.node) {
      session.node.port.onmessage = null;
      session.node.port.onmessageerror = null;
      session.node.onprocessorerror = null;
      try { session.node.port.postMessage({ type: 'cancel' }); } catch {}
      session.node.port.close();
    }
    for (const node of [session.source, session.node, session.mute]) {
      try { node?.disconnect(); } catch {}
    }
    session.context && (session.context.onstatechange = null);
    session.cleanup = Promise.resolve();
    try { session.cleanup = Promise.resolve(session.context?.close()).catch(() => {}); } catch {}
    session.chunks.length = 0;
    return session.cleanup;
  }

  function fail(session, error) {
    if (!active(session)) return;
    session.phase = 'failed';
    session.interrupt(error);
    session.reject(error);
    void cleanup(session);
    if (session.started) { try { onError(error); } catch {} }
  }

  function renewDelivery(session) {
    clearTimeout(session.deliveryTimer);
    if (session.phase === 'recording') {
      session.deliveryTimer = setTimeout(() => fail(session, new Error('PCM delivery stalled')), DELIVERY_TIMEOUT_MS);
    }
  }

  function finish(session) {
    if (session.phase !== 'recording') return session.result;
    session.phase = 'stopping';
    clearTimeout(session.limitTimer);
    clearTimeout(session.deliveryTimer);
    session.finalTimer = setTimeout(() => fail(session, new Error('Final PCM acknowledgment timed out')), FINAL_TIMEOUT_MS);
    try { session.node.port.postMessage({ type: 'finish' }); }
    catch (error) { fail(session, error); }
    return session.result;
  }

  function limit(session) {
    if (session.phase !== 'recording') return;
    finish(session);
    try { onLimit(); } catch {}
  }

  function receive(session, message) {
    if (!active(session)) return;
    if (message?.type === 'error') { fail(session, new Error(message.reason || 'PCM processor failed')); return; }
    if (message?.type === 'pcm') {
      if (!(message.samples instanceof Float32Array) || !message.samples.length
        || message.samples.length > Math.round(session.context.sampleRate / 10)
        || message.samples.some(value => !Number.isFinite(value))
        || message.sampleRate !== session.context.sampleRate
        || message.sequence !== session.sequence + 1 || message.startFrame !== session.frames
        || session.frames + message.samples.length > session.maxFrames) {
        fail(session, new Error('Invalid or discontinuous PCM chunk')); return;
      }
      session.chunks.push(message.samples);
      session.sequence++;
      session.frames += message.samples.length;
      renewDelivery(session);
      return;
    }
    if (message?.type === 'limit' && session.frames === session.maxFrames) { limit(session); return; }
    if (message?.type !== 'finished' || session.phase !== 'stopping'
      || message.sequence !== session.sequence || message.frames !== session.frames) {
      fail(session, new Error('Invalid final PCM acknowledgment')); return;
    }
    clearTimeout(session.finalTimer);
    const samples = new Float32Array(session.frames);
    let offset = 0;
    for (const chunk of session.chunks) { samples.set(chunk, offset); offset += chunk.length; }
    const result = { samples, sampleRate: session.context.sampleRate };
    void cleanup(session).then(() => {
      if (session.phase !== 'stopping') return;
      session.phase = 'done';
      session.resolve(result);
    });
  }

  async function start() {
    if (current && active(current)) throw new Error('Recording is already active');
    const session = { phase: 'starting', chunks: [], frames: 0, sequence: 0 };
    current = session;
    session.result = new Promise((resolve, reject) => { session.resolve = resolve; session.reject = reject; });
    session.interrupted = new Promise((_, reject) => { session.interrupt = reject; });
    // A session may be cancelled before any caller has requested its PCM result.
    session.result.catch(() => {});
    session.interrupted.catch(() => {});
    try {
      const Context = globalThis.AudioContext || globalThis.webkitAudioContext;
      if (!globalThis.navigator?.mediaDevices?.getUserMedia || typeof Context !== 'function'
        || typeof globalThis.AudioWorkletNode !== 'function') throw new Error('Microphone AudioWorklet capture unavailable');
      session.context = new Context();
      const context = session.context;
      if (!context.audioWorklet || !Number.isFinite(context.sampleRate)
        || context.sampleRate < 8000 || context.sampleRate > 192000) throw new Error('Unsupported PCM audio context');
      session.maxFrames = Math.floor(context.sampleRate * MAX_SECONDS);
      session.startupTimer = setTimeout(() => fail(session, new Error('Recording initialization timed out')), START_TIMEOUT_MS);
      // Resume and request permission in the start gesture, before awaiting either.
      const resumed = context.resume();
      const permission = navigator.mediaDevices.getUserMedia({ video: false, audio: {
        channelCount: { ideal: 1 }, echoCancellation: false, noiseSuppression: false, autoGainControl: false,
      } }).then(stream => {
        if (!active(session)) { stopTracks(stream); throw aborted(); }
        session.stream = stream;
        const tracks = stream.getAudioTracks();
        if (!tracks.length || tracks.some(track => track.readyState === 'ended')) throw new Error('No live microphone track');
        session.onEnded = () => fail(session, new Error('Microphone track ended'));
        for (const track of tracks) track.addEventListener('ended', session.onEnded, { once: true });
        return stream;
      });
      await Promise.race([Promise.all([permission, resumed]), session.interrupted]);
      if (!active(session)) throw aborted();
      if (context.state !== 'running') throw new Error('Audio context did not start');
      context.onstatechange = () => {
        if (active(session) && context.state !== 'running') fail(session, new Error('Audio context interrupted'));
      };
      await Promise.race([context.audioWorklet.addModule(new URL('./capture-worklet.mjs', import.meta.url)), session.interrupted]);
      if (!active(session)) throw aborted();
      session.node = new AudioWorkletNode(context, 'pronunciation-capture', {
        numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [1],
      });
      session.node.port.onmessage = event => receive(session, event.data);
      session.node.port.onmessageerror = () => fail(session, new Error('PCM message failed'));
      session.node.onprocessorerror = () => fail(session, new Error('PCM processor failed'));
      session.source = context.createMediaStreamSource(session.stream);
      session.mute = context.createGain();
      session.mute.gain.value = 0;
      session.source.connect(session.node);
      session.node.connect(session.mute);
      session.mute.connect(context.destination);
      session.started = true;
      session.phase = 'recording';
      clearTimeout(session.startupTimer);
      renewDelivery(session);
      session.limitTimer = setTimeout(() => limit(session), MAX_SECONDS * 1000);
    } catch (error) {
      fail(session, error);
      await cleanup(session);
      throw error;
    }
  }

  function stop() {
    if (!current || current.phase === 'starting') return Promise.reject(new Error('Recording has not started'));
    return finish(current);
  }

  async function cancel() {
    const session = current;
    current = null;
    if (!session) return;
    if (active(session)) {
      session.phase = 'cancelled';
      const error = aborted();
      session.interrupt(error);
      session.reject(error);
    }
    await cleanup(session);
  }

  return { start, stop, cancel };
}
