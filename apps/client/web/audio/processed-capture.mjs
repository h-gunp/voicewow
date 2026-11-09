import { createProcessedCaptureNode } from './noise-reduction.mjs';
const DELIVERY_TIMEOUT_MS = 3000;
const FINAL_TIMEOUT_MS = 1000;
const START_TIMEOUT_MS = 15000;
const aborted = () => new DOMException('Recording cancelled', 'AbortError');
const unsupportedRate = () => Object.assign(new Error('이 브라우저에서 48kHz 소음 억제를 시작하지 못했다. 다른 브라우저에서 다시 시도해야 한다.'), {captureReason: 'unsupported_sample_rate'});
const active = session => ['starting', 'recording', 'stopping'].includes(session.phase);
const stopTracks = stream => { for (const track of stream?.getTracks() || []) track.stop(); };
const speechKeys = ['speechFrames', 'nonSpeechFrames', 'uncertainFrames'];
const validSpeech = (value, frames) => value && speechKeys.every(key => Number.isInteger(value[key]) && value[key] >= 0)
  && value.totalFrames === Math.ceil(frames / 480) && speechKeys.reduce((sum, key) => sum + value[key], 0) === value.totalFrames;
function releaseNode(node) {
  if (!node) return;
  node.port.onmessage = node.port.onmessageerror = node.onprocessorerror = null;
  try { node.port.postMessage({type: 'cancel'}); } catch {}
  try { node.port.close(); } catch {}
  try { node.disconnect(); } catch {}
}

/** A user gesture must call start(). stop() waits for the final PCM acknowledgment.
 * onLimit fires after automatic stop begins; stop() then returns the same result.
 * Startup errors reject start(); later failures also call onError once.
 * PCM is continuous RNNoise output at 48kHz. VAD never crops or gates frames.
 * onChunk owns a copy that it may mutate/transfer without changing stop()'s result.
 */
export function createProcessedRecorder({ maxSeconds = 10, onChunk = () => {}, onLimit = () => {}, onError = () => {} } = {}) {
  if (!Number.isFinite(maxSeconds) || maxSeconds <= 0 || maxSeconds > 20) throw new RangeError('Capture duration must be at most 20 seconds');
  let current;

  function cleanup(session) {
    if (session.cleaned) return session.cleanup;
    session.cleaned = true;
    session.loading.abort();
    for (const timer of ['startupTimer', 'deliveryTimer', 'limitTimer', 'finalTimer']) clearTimeout(session[timer]);
    for (const track of session.stream?.getAudioTracks() || []) track.removeEventListener('ended', session.onEnded);
    stopTracks(session.stream);
    releaseNode(session.node);
    for (const node of [session.source, session.mute]) {
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
        || session.frames + message.samples.length > session.maxFrames
        || !validSpeech(message.speech, session.frames + message.samples.length)) {
        fail(session, new Error('Invalid or discontinuous PCM chunk')); return;
      }
      session.chunks.push(message.samples);
      session.sequence++;
      session.frames += message.samples.length;
      renewDelivery(session);
      try { onChunk({samples: message.samples.slice(), sampleRate: 48000, startFrame: message.startFrame, speech: {...message.speech}}); }
      catch (error) { fail(session, error); }
      return;
    }
    if (message?.type === 'limit' && session.frames === session.maxFrames) { limit(session); return; }
    if (message?.type !== 'finished' || session.phase !== 'stopping'
      || message.sequence !== session.sequence || message.frames !== session.frames
      || !validSpeech(message.speech, session.frames) || !Number.isFinite(message.rawVariance) || message.rawVariance < 0) {
      fail(session, new Error('Invalid final PCM acknowledgment')); return;
    }
    clearTimeout(session.finalTimer);
    // VAD alone must not discard a weak/fricative utterance. This raw-signal
    // threshold is the existing pronunciation analysis silence check.
    if (session.frames >= 9600 && message.rawVariance < 1e-10 && message.speech.speechFrames === 0) {
      fail(session, Object.assign(new Error('말소리가 들어오지 않았다. 마이크를 확인하고 다시 녹음해야 한다.'), {captureReason: 'no_speech'}));
      return;
    }
    const samples = new Float32Array(session.frames);
    let offset = 0;
    for (const chunk of session.chunks) { samples.set(chunk, offset); offset += chunk.length; }
    const result = { samples, sampleRate: session.context.sampleRate, speech: {...message.speech} };
    void cleanup(session).then(() => {
      if (session.phase !== 'stopping') return;
      session.phase = 'done';
      session.resolve(result);
    });
  }

  async function start() {
    if (current && active(current)) throw new Error('Recording is already active');
    const session = { phase: 'starting', chunks: [], frames: 0, sequence: 0, loading: new AbortController() };
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
      try { session.context = new Context({sampleRate: 48000}); }
      catch (error) { if (error?.name === 'NotSupportedError') throw unsupportedRate(); throw error; }
      const context = session.context;
      if (!context.audioWorklet) throw new Error('Microphone AudioWorklet capture unavailable');
      if (context.sampleRate !== 48000) throw unsupportedRate();
      session.maxFrames = Math.floor(context.sampleRate * maxSeconds);
      session.startupTimer = setTimeout(() => fail(session, new Error('Recording initialization timed out')), START_TIMEOUT_MS);
      // Resume and request permission in the start gesture, before awaiting either.
      const resumed = context.resume();
      const permission = navigator.mediaDevices.getUserMedia({ video: false, audio: {
        channelCount: { ideal: 1 }, sampleRate: {ideal: 48000}, echoCancellation: false, noiseSuppression: false, autoGainControl: false,
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
      const prepared = createProcessedCaptureNode(context, session.loading.signal, maxSeconds).then(node => {
        // Cancellation can win after loader readiness but before this await resumes.
        if (!active(session)) { releaseNode(node); throw aborted(); }
        session.node = node;
        return node;
      });
      await Promise.race([prepared, session.interrupted]);
      if (!active(session)) throw aborted();
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
      session.limitTimer = setTimeout(() => limit(session), maxSeconds * 1000);
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
