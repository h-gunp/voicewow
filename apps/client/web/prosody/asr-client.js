// Lazy local-only worker client. No microphone acquisition, network calls,
// remote fallback, scripts, persistence or telemetry in this module.
const INIT_TIMEOUT_MS = 6 * 60 * 1000;
const DECODE_TIMEOUT_MS = 15000;

function stoppedError() {
  const error = new Error('ASR stopped'); error.name = 'AbortError'; return error;
}

export class AsrClient {
  constructor({ onResult = () => {}, onProgress = () => {}, onError = () => {} } = {}) {
    if ([onResult, onProgress, onError].some(callback => typeof callback !== 'function')) {
      throw new TypeError('ASR callbacks must be functions');
    }
    this.onResult = onResult; this.onProgress = onProgress; this.onError = onError;
    this._worker = null; this._prepared = false; this._initializing = null; this._pending = null;
    this._nextSequence = 1; this._sampleRate = null;
  }

  get prepared() { return this._prepared; }

  _settle(slot, error, value) {
    const request = this[slot];
    if (!request) return;
    this[slot] = null; clearTimeout(request.timer);
    if (error) request.reject(error); else request.resolve(value);
  }

  _dispose(error) {
    const worker = this._worker;
    this._worker = null; this._prepared = false; this._nextSequence = 1; this._sampleRate = null;
    if (worker) {
      worker.onmessage = null; worker.onerror = null; worker.onmessageerror = null;
      try { worker.terminate(); } catch {}
    }
    this._settle('_initializing', error); this._settle('_pending', error);
  }

  _fail(error) {
    if (!this._worker && !this._initializing && !this._pending) return;
    const failure = error instanceof Error ? error : new Error('ASR worker failed');
    this._dispose(failure);
    try { Promise.resolve(this.onError(failure)).catch(() => {}); } catch {}
  }

  /** Concurrent callers share initialization; stop/failure permit a fresh retry. */
  prepare() {
    if (this._prepared) return Promise.resolve();
    if (this._initializing) return this._initializing.promise;
    if (typeof globalThis.Worker !== 'function' || typeof globalThis.WebAssembly !== 'object') {
      return Promise.reject(new Error('Local ASR requires Worker and WebAssembly'));
    }
    if (globalThis.isSecureContext === false) return Promise.reject(new Error('Local ASR requires a secure context'));
    let resolve, reject;
    const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
    this._initializing = { promise, resolve, reject,
      timer: setTimeout(() => this._fail(new Error('ASR initialization timed out')), INIT_TIMEOUT_MS) };
    try {
      const worker = new Worker(new URL('./asr-worker.js', import.meta.url), { type: 'classic', name: 'voicemate-asr' });
      this._worker = worker;
      worker.onmessage = event => { if (this._worker === worker) this._message(event.data, worker); };
      worker.onerror = event => {
        if (this._worker !== worker) return;
        event.preventDefault?.(); this._fail(new Error('ASR worker execution failed'));
      };
      worker.onmessageerror = () => { if (this._worker === worker) this._fail(new Error('ASR worker message failed')); };
      worker.postMessage({ type: 'init' });
    } catch (error) { this._fail(error); }
    return promise;
  }

  _message(message, worker) {
    if (message?.type === 'error') {
      this._fail(new Error(typeof message.message === 'string' ? message.message : 'ASR worker failed')); return;
    }
    if (message?.type === 'progress') {
      if (!this._initializing || !Number.isFinite(message.loaded) || !Number.isFinite(message.total)
        || message.loaded < 0 || message.total < message.loaded) {
        this._fail(new Error('Invalid ASR download progress')); return;
      }
      try {
        Promise.resolve(this.onProgress({ loaded: message.loaded, total: message.total }))
          .catch(error => { if (this._worker === worker) this._fail(error); });
      } catch (error) { this._fail(error); }
      return;
    }
    if (message?.type === 'ready') {
      if (!this._initializing || this._prepared) { this._fail(new Error('Unexpected ASR ready message')); return; }
      this._prepared = true; this._settle('_initializing', null); return;
    }
    const pending = this._pending;
    if (message?.type !== 'result' || !this._prepared || !pending || pending.received
      || message.sequence !== pending.sequence || typeof message.text !== 'string'
      || message.text.length > 8000 || typeof message.endpoint !== 'boolean') {
      this._fail(new Error('Invalid or out-of-order ASR result')); return;
    }
    pending.received = true;
    const result = { sequence: message.sequence, text: message.text, endpoint: message.endpoint };
    // A consumer can update alignment asynchronously. Do not acknowledge the PCM
    // or permit another chunk until that callback has settled too.
    try {
      Promise.resolve(this.onResult(result)).then(() => {
        if (this._worker !== worker || this._pending !== pending) return;
        this._nextSequence++; this._settle('_pending', null, result);
      }, error => { if (this._worker === worker) this._fail(error); });
    } catch (error) { this._fail(error); }
  }

  /** Consumes ownership of samples.buffer by transfer. Caller must not reuse it.
   * Resolves only after the matching worker result; never queues audio.
   */
  consume({ samples, sampleRate, sequence } = {}) {
    if (!this._prepared || !this._worker) return Promise.reject(new Error('ASR is not prepared'));
    if (this._pending) return Promise.reject(new Error('ASR already has an outstanding chunk'));
    if (!(samples instanceof Float32Array) || !samples.length
      || !Number.isInteger(sampleRate) || sampleRate < 8000 || sampleRate > 192000
      || samples.length > sampleRate || samples.some(value => !Number.isFinite(value))
      || !(samples.buffer instanceof ArrayBuffer) || samples.byteOffset !== 0 || samples.byteLength !== samples.buffer.byteLength
      || !Number.isSafeInteger(sequence) || sequence !== this._nextSequence
      || (this._sampleRate !== null && sampleRate !== this._sampleRate)) {
      return Promise.reject(new Error('Invalid or discontinuous ASR audio'));
    }
    this._sampleRate = sampleRate;
    return new Promise((resolve, reject) => {
      this._pending = { sequence, received: false, resolve, reject,
        timer: setTimeout(() => this._fail(new Error('ASR decoding timed out')), DECODE_TIMEOUT_MS) };
      try { this._worker.postMessage({ type: 'audio', samples, sampleRate, sequence }, [samples.buffer]); }
      catch (error) { this._fail(error); }
    });
  }

  /** Terminates inference/download work and rejects waiters without onError. */
  stop() { this._dispose(stoppedError()); }
}
