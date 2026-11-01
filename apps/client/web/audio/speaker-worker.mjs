// PCM messages use Float32Array; scalar messages are reserved for controls.
export function createSpeakerWorker(makeWorker, {timeoutMs = 10000, loadingTimeoutMs = 60000, setTimer = setTimeout, clearTimer = clearTimeout} = {}) {
  if (![timeoutMs,loadingTimeoutMs].every(value=>Number.isFinite(value)&&value>0)) throw new RangeError('Invalid worker timeout');
  let worker = null, pending = null, nextId = 0, ready = false;
  function clear() {
    if (!pending) return null;
    const job = pending; pending = null;
    clearTimer(job.timer);
    if (job.pcm instanceof Float32Array) job.pcm.fill(0);
    worker.removeEventListener('message', job.onMessage);
    worker.removeEventListener('error', job.onError);
    worker.removeEventListener('messageerror', job.onError);
    return job;
  }
  function cancel() {
    const job = clear();
    if (worker) { worker.terminate(); worker = null; ready = false; }
    job?.reject(new DOMException('Speaker worker cancelled', 'AbortError'));
  }
  return {
    run(value, onReady = () => {}) {
      if (!(value instanceof Float32Array) && !['string','number','boolean'].includes(typeof value)) return Promise.reject(new TypeError('PCM or scalar control required'));
      if (pending) return Promise.reject(new Error('Speaker worker is busy'));
      worker ??= makeWorker();
      return new Promise((resolve, reject) => {
        const id = ++nextId;
        const timeout = () => { clear(); worker.terminate(); worker = null; ready = false; reject(new Error('Speaker worker timeout')); };
        const onMessage = ({data}) => {
          if (data?.id !== id) return;
          if (data.phase === 'inference') { if (!ready) { ready = true; clearTimer(pending.timer); pending.timer = setTimer(timeout, timeoutMs); onReady(); } return; }
          clear();
          if (data.error) { worker.terminate(); worker = null; ready = false; reject(new Error('Speaker worker failed')); }
          else resolve(data.result);
        };
        const onError = () => { clear(); worker.terminate(); worker = null; ready = false; reject(new Error('Speaker worker failed')); };
        const pcm = value instanceof Float32Array ? value.slice() : value;
        pending = {resolve, reject, onMessage, onError, pcm, timer: null};
        worker.addEventListener('message', onMessage);
        worker.addEventListener('error', onError);
        worker.addEventListener('messageerror', onError);
        pending.timer = setTimer(timeout, ready ? timeoutMs : loadingTimeoutMs);
        try { worker.postMessage({id, value: pcm}); } catch { onError(); }
      });
    },
    cancel,
  };
}
