// Local PCM transport only. Receives an existing stream; never requests a mic,
// uploads audio, or changes ownership of its tracks. The caller owns the ASR.
const INITIALIZATION_TIMEOUT_MS = 15000;
const CHUNK_SECONDS = 0.1;
const MAX_IN_FLIGHT = 4;

function abortError() { return new DOMException('PCM capture stopped', 'AbortError'); }

/** onChunk({samples, sampleRate, sequence, startFrame}) may return a Promise.
 * Chunks are delivered serially. Resolve only when the consumer has accepted
 * the chunk; four unacknowledged chunks cause an explicit transport error.
 * stop() discards any undelivered/pending tail and does not finalize ASR.
 * Context sample rate is preserved; resampling belongs to the ASR consumer.
 */
export async function startAsrPcmBridge({ stream, onChunk, onError = () => {}, signal } = {}) {
  if (typeof onChunk !== 'function' || typeof onError !== 'function') throw new TypeError('PCM callbacks required');
  const tracks = stream?.getAudioTracks?.();
  if (!tracks?.length || tracks.some(track => track.readyState === 'ended')) throw new Error('No live audio stream');
  if (signal?.aborted) throw abortError();
  const Context = globalThis.AudioContext || globalThis.webkitAudioContext;
  if (typeof Context !== 'function' || typeof globalThis.AudioWorkletNode !== 'function') throw new Error('AudioWorklet unavailable');
  let context, source, node, mute, stopped = false, ready = false, busy = false;
  let closePromise = Promise.resolve(), expectedSequence = 1, expectedFrame = 0;
  const queue = [];
  let cancelInitialization;
  const cancelled = new Promise((_, reject) => { cancelInitialization = reject; });
  // This rejection is raced below, but can occur during synchronous setup too.
  cancelled.catch(() => {});
  const stop = () => {
    if (stopped) return closePromise;
    stopped = true; queue.length = 0;
    signal?.removeEventListener('abort', onAbort);
    for (const track of tracks) track.removeEventListener?.('ended', onEnded);
    cancelInitialization(abortError());
    if (node) {
      node.port.onmessage = null; node.onprocessorerror = null;
      try { node.port.postMessage({ type: 'stop' }); } catch {}
      try { node.port.close(); } catch {}
    }
    for (const owned of [source, node, mute]) { try { owned?.disconnect(); } catch {} }
    if (context) {
      context.onstatechange = null;
      try { closePromise = Promise.resolve(context.close()).catch(() => {}); } catch {}
    }
    return closePromise;
  };
  const fail = error => {
    if (stopped) return;
    const report = error instanceof Error ? error : new Error('PCM transport failed');
    stop();
    if (ready) { try { onError(report); } catch {} }
  };
  const onAbort = () => { stop(); };
  const onEnded = () => fail(new Error('Audio stream ended'));
  const drain = async () => {
    if (busy || stopped || !ready) return;
    busy = true;
    try {
      while (!stopped && queue.length) {
        const chunk = queue.shift();
        await onChunk(chunk);
        if (!stopped) node.port.postMessage({ type: 'ack', sequence: chunk.sequence });
      }
    } catch (error) { fail(error); }
    finally { busy = false; }
  };
  signal?.addEventListener('abort', onAbort, { once: true });
  const timer = setTimeout(() => cancelInitialization(new Error('PCM initialization timed out')), INITIALIZATION_TIMEOUT_MS);
  try {
    context = new Context();
    if (!context.audioWorklet || !Number.isFinite(context.sampleRate) || context.sampleRate < 8000 || context.sampleRate > 192000) {
      throw new Error('Unsupported PCM audio context');
    }
    const chunkFrames = Math.round(context.sampleRate * CHUNK_SECONDS);
    await Promise.race([context.audioWorklet.addModule(new URL('./asr-pcm-worklet.js', import.meta.url)), cancelled]);
    if (stopped) throw abortError();
    if (tracks.some(track => track.readyState === 'ended')) throw new Error('Audio stream ended during startup');
    node = new AudioWorkletNode(context, 'voicemate-asr-pcm', {
      numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [1],
      processorOptions: { chunkFrames, maxInFlight: MAX_IN_FLIGHT },
    });
    node.port.onmessage = event => {
      if (stopped) return;
      const message = event.data;
      if (message?.type === 'error') { fail(new Error(`PCM transport: ${message.reason || 'processor failure'}`)); return; }
      if (message?.type !== 'pcm' || !(message.samples instanceof Float32Array)
        || message.samples.length !== chunkFrames || message.samples.some(value => !Number.isFinite(value))
        || message.sampleRate !== context.sampleRate || message.sequence !== expectedSequence
        || message.startFrame !== expectedFrame || queue.length >= MAX_IN_FLIGHT) {
        fail(new Error('Invalid or discontinuous PCM chunk')); return;
      }
      expectedSequence++; expectedFrame += chunkFrames;
      queue.push({ samples: message.samples, sampleRate: message.sampleRate,
        sequence: message.sequence, startFrame: message.startFrame });
      void drain();
    };
    node.onprocessorerror = () => fail(new Error('PCM processor failed'));
    source = context.createMediaStreamSource(stream);
    mute = context.createGain(); mute.gain.value = 0;
    source.connect(node); node.connect(mute); mute.connect(context.destination);
    for (const track of tracks) track.addEventListener?.('ended', onEnded, { once: true });
    await Promise.race([context.resume(), cancelled]);
    if (stopped) throw abortError();
    if (tracks.some(track => track.readyState === 'ended')) throw new Error('Audio stream ended during startup');
    if (context.state !== 'running') throw new Error('PCM context did not start');
    ready = true;
    void drain();
    context.onstatechange = () => {
      if (!stopped && context.state !== 'running') fail(new Error('PCM context interrupted'));
    };
    return { stop, sampleRate: context.sampleRate, chunkFrames };
  } catch (error) { await stop(); throw error; }
  finally { clearTimeout(timer); }
}
