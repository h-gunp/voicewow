import { createPhoneEngine, WEB_MODEL_ASSET } from './phone-engine.mjs';
import { createModelLoader } from './model-loader.mjs';

let engine = null, busy = false;
self.onmessage = async event => {
  const { type, id, samples, sampleRate } = event.data ?? {};
  if (!Number.isSafeInteger(id) || id < 1 || !['prepare', 'recognize'].includes(type)) return;
  if (busy) { self.postMessage({ type: 'error', id, message: '이전 분석이 진행 중이다.' }); return; }
  busy = true;
  try {
    if (type === 'prepare') {
      const onProgress = message => self.postMessage({ type: 'progress', id, message });
      engine ??= await createPhoneEngine({ loadAsset: createModelLoader(onProgress), modelAsset: WEB_MODEL_ASSET, onProgress });
      self.postMessage({ type: 'ready', id });
    } else {
      if (!engine) throw new Error('발음 모델을 먼저 준비해야 한다.');
      self.postMessage({ type: 'result', id, result: await engine.recognize(samples, sampleRate) });
    }
  } catch (error) {
    self.postMessage({ type: 'error', id, message: /[가-힣]/u.test(error?.message ?? '')
      ? error.message : '이 기기에서 발음 분석을 실행하지 못했다. 연결과 메모리를 확인해야 한다.' });
  } finally { busy = false; }
};
