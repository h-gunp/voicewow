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
        const response = await fetch(new URL('./vendor/rnnoise/rnnoise.wasm', import.meta.url), {
          signal: request.signal, mode: 'same-origin', credentials: 'same-origin',
        });
        if (finished) return;
        if (!response.ok) throw failure('load_failed');
        const wasmBinary = new Uint8Array(await response.arrayBuffer());
        if (finished) return;
        let vadBinary = null;
        const vadRequest = new AbortController();
        let cancelVad;
        const cancelled = new Promise(resolve => { cancelVad = () => { vadRequest.abort(); resolve(null); }; });
        request.signal.addEventListener('abort', cancelVad, {once:true});
        let vadTimer;
        try {
          const timeout = new Promise(resolve => { vadTimer = setTimeout(() => { vadRequest.abort(); resolve(null); }, 1500); });
          const download = (async () => {
            const vadResponse = await fetch(new URL('./vendor/libfvad/libfvad.wasm', import.meta.url), {
              signal: vadRequest.signal, mode: 'same-origin', credentials: 'same-origin',
            });
            return vadResponse.ok ? new Uint8Array(await vadResponse.arrayBuffer()) : null;
          })();
          vadBinary = await Promise.race([download, timeout, cancelled]);
        } catch { /* The existing level meter remains available without VAD. */ }
        finally { clearTimeout(vadTimer); request.signal.removeEventListener('abort', cancelVad); }
        if (finished) return;
        await context.audioWorklet.addModule(new URL('./noise-reduction-worklet.mjs', import.meta.url).href);
        if (finished) return;
        node = new AudioWorkletNode(context, 'voicemate-noise-meter', {
          numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [1],
          processorOptions: {wasmBinary, vadBinary},
        });
        if (finished) { dispose(node); return; }
        node.port.onmessage = ({data}) => {
          if (data?.type === 'ready') finish();
          else if (data?.type === 'error') finish(failure('load_failed'));
        };
        node.port.onmessageerror = node.onprocessorerror = () => finish(failure('load_failed'));
      } catch {
        finish(failure('load_failed'));
      }
    })();
  });
}
