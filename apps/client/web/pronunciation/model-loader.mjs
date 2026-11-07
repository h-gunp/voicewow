import { MODEL_REVISION } from './phone-engine.mjs';

const BASE = `https://huggingface.co/chegrowk/ko-phone-int8/resolve/${MODEL_REVISION}/`;
const CACHE = `voicemate-pronunciation-${MODEL_REVISION}`;

async function readVerified(response, asset, progress) {
  if (!response.ok) throw new Error('발음 모델을 내려받지 못했다. 연결을 확인하고 다시 시도해야 한다.');
  // Fetch may decode gzip while Content-Length still describes the transfer.
  const bytes = new Uint8Array(asset.bytes);
  const reader = response.body?.getReader();
  if (!reader) throw new Error('이 브라우저에서 모델 다운로드를 읽지 못했다.');
  let received = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (received + value.length > bytes.length) throw new Error('모델 파일 크기가 일치하지 않는다.');
      bytes.set(value, received); received += value.length;
      progress?.(received);
    }
  } finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
  if (received !== bytes.length) throw new Error('모델 파일 크기가 일치하지 않는다.');
  const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), b => b.toString(16).padStart(2, '0')).join('');
  if (hash !== asset.sha256) throw new Error('모델 파일 해시가 일치하지 않는다. 다시 내려받아야 한다.');
  return bytes;
}

export function createModelLoader(onProgress = () => {}) {
  return async asset => {
    if (!/^(?:[a-z_]+\.json|onnx\/model_quantized\.onnx)$/.test(asset.path)
      || !Number.isSafeInteger(asset.bytes) || asset.bytes < 1 || asset.bytes > 356129122
      || !/^[a-f0-9]{64}$/.test(asset.sha256)) throw new Error('모델 파일 정보가 올바르지 않다.');
    const url = BASE + asset.path;
    let cache;
    try { cache = await globalThis.caches?.open(CACHE); }
    catch { onProgress('모델 캐시를 사용할 수 없어 이번 실행에만 내려받는다.'); }
    try {
      const cached = await cache?.match(url);
      if (cached) {
        onProgress('기기에 저장된 발음 모델 캐시를 검증 중이다.');
        try { return await readVerified(cached, asset); }
        catch { await cache.delete(url); }
      }
    } catch { cache = undefined; }
    onProgress('발음 모델 최초 다운로드는 약 356MB다. 음성은 기기 밖으로 보내지 않는다.');
    let lastPercent = -1;
    const bytes = await readVerified(await fetch(url, { credentials: 'omit', referrerPolicy: 'no-referrer' }), asset, received => {
      if (asset.bytes < 1000000) return;
      const percent = Math.floor(received * 100 / asset.bytes);
      if (percent !== lastPercent) {
        lastPercent = percent;
        onProgress(`발음 모델 다운로드 ${percent}% · ${(received / 1000000).toFixed(1)} / 356.1MB다.`);
      }
    });
    try { await cache?.put(url, new Response(bytes, { headers: { 'Content-Length': String(bytes.length) } })); }
    catch { onProgress('모델 검증은 끝났으나 캐시 저장 공간이 부족해 다음 실행에 다시 내려받는다.'); }
    return bytes;
  };
}
