import { createPhoneEngine } from './phone-engine.mjs';

let engine = null, busy = false;
self.onmessage = async event => {
  const { type, id, samples, sampleRate } = event.data ?? {};
  if (!Number.isSafeInteger(id) || id < 1 || !['prepare', 'recognize'].includes(type)) return;
  if (busy) { self.postMessage({ type: 'error', id, message: '이전 분석이 진행 중이다.' }); return; }
  busy = true;
  try {
    if (type === 'prepare') {
      engine ??= await createPhoneEngine({ loadAsset: async asset => {
        const response = await fetch(new URL(`../../.local/pronunciation-spike/${asset.path}`, import.meta.url), { credentials: 'omit', cache: 'no-store' });
        if (!response.ok) throw new Error('로컬 모델 파일을 찾을 수 없다. 다운로드 도구를 먼저 실행해야 한다.');
        const declared = response.headers.get('content-length');
        if (declared !== null && Number(declared) !== asset.bytes) throw new Error('로컬 모델 파일 크기가 일치하지 않는다.');
        return response.arrayBuffer();
      } });
      self.postMessage({ type: 'ready', id });
    } else {
      if (!engine) throw new Error('모델을 먼저 준비해야 한다.');
      const result = await engine.recognize(samples, sampleRate);
      self.postMessage({ type: 'result', id, result });
    }
  } catch (error) {
    self.postMessage({ type: 'error', id, message: error instanceof Error && /[가-힣]/u.test(error.message)
      ? error.message : '이 기기에서 분석을 실행하지 못했다. 메모리와 모델 파일을 확인해야 한다.' });
  } finally { busy = false; }
};
