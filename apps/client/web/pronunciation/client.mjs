export function createPhoneClient({ workerUrl = new URL('./worker.mjs', import.meta.url) } = {}) {
  let worker = null, pending = null, sequence = 0, ready = false;
  const reset = error => {
    if (pending) { clearTimeout(pending.timer); pending.reject(error); pending = null; }
    if (worker) { worker.onmessage = null; worker.onerror = null; worker.onmessageerror = null; worker.terminate(); }
    worker = null; ready = false;
  };
  const request = (type, payload = {}, onProgress) => {
    if (pending) return Promise.reject(new Error('이전 작업이 진행 중이다.'));
    return new Promise((resolve, reject) => {
      const id = ++sequence;
      try {
        if (!worker) {
          const current = new Worker(workerUrl, { type: 'module' });
          worker = current;
          current.onmessage = event => {
            const message = event.data;
            if (current !== worker || !pending || message?.id !== pending.id) return;
            if (pending.type === 'prepare' && message.type === 'progress' && typeof message.message === 'string') {
              try { pending.onProgress?.(message.message); } catch {}
              return;
            }
            if (message.type === 'error') { reset(new Error(message.message || '분석에 실패했다.')); return; }
            if (pending.type === 'prepare' && message.type === 'ready') ready = true;
            else if (pending.type === 'recognize' && message.type === 'result') {
              const result = message.result;
              if (!Array.isArray(result?.phones) || result.phones.length > 1000
                || result.phones.some(item => typeof item?.phone !== 'string' || item.phone.length > 32)
                || !Array.isArray(result.display?.segments) || typeof result.display.text !== 'string' || result.display.text.length > 4000
                || !Number.isFinite(result.inferenceMs) || !Number.isFinite(result.duration) || result.duration <= 0 || result.duration > 20) {
                reset(new Error('분석 결과 형식이 올바르지 않다.')); return;
              }
            } else { reset(new Error('분석 결과 순서가 올바르지 않다.')); return; }
            const complete = pending; pending = null; clearTimeout(complete.timer);
            complete.resolve(message.result);
          };
          current.onerror = () => { if (current === worker) reset(new Error('분석기가 중단됐다. 모델을 다시 준비해야 한다.')); };
          current.onmessageerror = () => { if (current === worker) reset(new Error('분석 결과를 전달하지 못했다.')); };
        }
        pending = { id, type, resolve, reject, onProgress, timer: setTimeout(() => reset(new Error('처리 시간이 초과됐다. 연결과 기기 메모리를 확인한 뒤 다시 시도해야 한다.')), type === 'prepare' ? 600000 : 180000) };
        worker.postMessage({ type, id, ...payload }, payload.samples ? [payload.samples.buffer] : []);
      } catch (error) { reset(error); reject(error); }
    });
  };
  return {
    get ready() { return ready; },
    prepare(onProgress) {
      if (ready && !pending) { onProgress?.('기기 안의 발음 모델이 준비됐다.'); return Promise.resolve(); }
      return request('prepare', {}, onProgress);
    },
    recognize(samples, sampleRate) {
      if (!ready) return Promise.reject(new Error('모델을 먼저 준비해야 한다.'));
      if (!(samples instanceof Float32Array) || sampleRate !== 16000 || samples.length < 3200 || samples.length > 320000
        || samples.some(value => !Number.isFinite(value) || Math.abs(value) > 1.001)) return Promise.reject(new Error('오디오 입력이 올바르지 않다.'));
      return request('recognize', { samples: samples.slice(), sampleRate });
    },
    cancel() { reset(new DOMException('분석을 취소했다.', 'AbortError')); },
  };
}
