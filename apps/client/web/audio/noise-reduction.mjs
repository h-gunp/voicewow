function failure(captureReason) {
  return Object.assign(new Error(captureReason), {captureReason});
}

function dispose(node) {
  if (!node) return;
  node.port.onmessage = null;
  node.port.onmessageerror = null;
  node.onprocessorerror = null;
  try { node.port.postMessage({type: 'dispose'}); } catch { /* The processor may already have failed. */ }
  try { node.port.close(); } catch { /* Continue releasing a failed port's node. */ }
  try { node.disconnect(); } catch { /* The node may already be disconnected. */ }
}

/** The caller owns the ready node and context; this loader owns only initialization. */
export async function createNoiseReductionNode(context, signal) {
  return createNode(context, signal, false);
}

export async function createProcessedCaptureNode(context, signal, maxSeconds = 10, noiseReductionEnabled = true) {
  if (!Number.isFinite(maxSeconds) || maxSeconds <= 0 || maxSeconds > 20) throw new RangeError('Capture duration must be at most 20 seconds');
  if (typeof noiseReductionEnabled !== 'boolean') throw new TypeError('Noise reduction setting must be boolean');
  return createNode(context, signal, true, maxSeconds, noiseReductionEnabled);
}

async function createNode(context, signal, capture, maxSeconds, noiseReductionEnabled = true) {
  if (signal?.aborted) throw new DOMException('Noise reduction cancelled', 'AbortError');
  if (context.sampleRate !== 48000) throw failure('unsupported_sample_rate');
  if (typeof globalThis.AudioWorkletNode !== 'function'
      || typeof globalThis.WebAssembly?.instantiate !== 'function'
      || typeof context.audioWorklet?.addModule !== 'function'
      || typeof globalThis.fetch !== 'function') throw failure('unsupported');

  return new Promise((resolve, reject) => {
    const request = new AbortController();
    let node, finished = false;
    const finish = error => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      signal?.removeEventListener('abort', cancel);
      if (node) {
        node.port.onmessage = null;
        node.port.onmessageerror = null;
        node.onprocessorerror = null;
      }
      if (error) {
        request.abort();
        dispose(node);
        reject(error);
      } else resolve(node);
    };
    const cancel = () => finish(new DOMException('Noise reduction cancelled', 'AbortError'));
    const timer = setTimeout(() => finish(failure('load_timeout')), 10000);
    signal?.addEventListener('abort', cancel, {once: true});

    void (async () => {
      try {
        const download = async path => {
          const response = await fetch(new URL(path, import.meta.url), {
            signal: request.signal, mode: 'same-origin', credentials: 'same-origin',
          });
          if (finished) return null;
          if (!response.ok) throw failure('load_failed');
          return new Uint8Array(await response.arrayBuffer());
        };
        // Independent cold downloads share the initialization deadline.
        const [wasmBinary, vadBinary] = await Promise.all([
          noiseReductionEnabled ? download('./vendor/rnnoise/rnnoise.wasm') : Promise.resolve(null),
          download('./vendor/libfvad/libfvad.wasm').catch(error => { if (capture) throw error; return null; }),
          Promise.resolve().then(() => context.audioWorklet.addModule(new URL(capture ? './processed-capture-worklet.mjs' : './noise-reduction-worklet.mjs', import.meta.url).href)),
        ]);
        if (finished) return;
        node = new AudioWorkletNode(context, capture ? 'voicemate-processed-capture' : 'voicemate-noise-meter', {
          numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [1],
          processorOptions: {wasmBinary, vadBinary, ...(capture ? {maxSeconds, ...(!noiseReductionEnabled ? {noiseReductionEnabled: false} : {})} : {})},
        });
        if (finished) { dispose(node); return; }
        node.port.onmessage = ({data}) => {
          if (data?.type === 'ready') {
            if (capture && data.vadStatus !== 'ready') { finish(failure('load_failed')); return; }
            node.vadStatus = vadBinary ? (data.vadStatus || 'unknown') : 'load_failed';
            finish();
          }
          else if (data?.type === 'error') finish(failure('load_failed'));
        };
        node.port.onmessageerror = node.onprocessorerror = () => finish(failure('load_failed'));
      } catch {
        finish(failure('load_failed'));
      }
    })();
  });
}
