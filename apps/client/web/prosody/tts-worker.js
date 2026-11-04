// Only fixed public model URLs are fetched. Text and synthesized audio stay here.
import { createSpeechEngine, MODEL_BASE, MODEL_REVISION, MODEL_DOWNLOAD_BYTES } from './vendor/supertonic/engine.js';

const CACHE_NAME = `voicemate-tts-model-${MODEL_REVISION}`;
let engine = null, busy = false;
let loaded = 0;
const progress = (id, value) => self.postMessage({ type: 'progress', id, ...value });

async function modelCache() {
  try { return await caches.open(CACHE_NAME); } catch { return null; }
}

async function loadModelAsset(asset, id) {
  const url = MODEL_BASE + asset.path;
  const cache = await modelCache();
  let response = null;
  try { response = await cache?.match(url); } catch { /* browser cache may be unavailable */ }
  const cached = Boolean(response);
  if (!response) {
    try { response = await fetch(url, { credentials: 'omit', cache: 'force-cache' }); }
    catch { throw new Error('모델을 내려받지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요.'); }
  }
  if (!response.ok) throw new Error('모델 파일을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.');
  const cacheResponse = !cached && cache ? response.clone() : null;
  // Cache only immutable public model files, never scripts, recordings or output.
  const cacheWrite = cacheResponse ? cache.put(url, cacheResponse).catch(() => {}) : Promise.resolve();
  const chunks = [];
  let bytesRead = 0, lastProgress = 0;
  if (response.body?.getReader) {
    const reader = response.body.getReader();
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(value); bytesRead += value.byteLength;
      if (performance.now() - lastProgress > 150) {
        lastProgress = performance.now();
        const totalLoaded = Math.min(MODEL_DOWNLOAD_BYTES, loaded + bytesRead);
        progress(id, { phase: 'loading', loaded: totalLoaded, total: MODEL_DOWNLOAD_BYTES,
          message: `가이드 준비 중 · ${Math.floor(totalLoaded / MODEL_DOWNLOAD_BYTES * 100)}%${cached ? ' (저장된 모델)' : ''}` });
      }
    }
  } else {
    const array = new Uint8Array(await response.arrayBuffer()); chunks.push(array); bytesRead = array.byteLength;
  }
  if (bytesRead !== asset.bytes) {
    await cacheWrite;
    try { await cache?.delete(url); } catch {}
    throw new Error('모델 파일이 완전히 받아지지 않았어요. 다시 시도해 주세요.');
  }
  const bytes = new Uint8Array(bytesRead);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  loaded += asset.bytes;
  progress(id, { phase: 'loading', loaded, total: MODEL_DOWNLOAD_BYTES,
    message: `가이드 준비 중 · ${Math.floor(loaded / MODEL_DOWNLOAD_BYTES * 100)}%` });
  // A cache quota failure cannot stop synthesis. Finishing the write before
  // another large file reduces overlapping cache/download memory pressure.
  await cacheWrite;
  return bytes.buffer;
}

self.onmessage = async event => {
  const { type, id, text } = event.data || {};
  if (type !== 'generate' || !Number.isInteger(id)) return;
  if (busy) { self.postMessage({ type: 'error', id, message: '이전 가이드를 준비 중이에요. 잠시 기다려 주세요.' }); return; }
  busy = true;
  try {
    if (!engine) {
      loaded = 0;
      progress(id, { phase: 'loading', loaded: 0, total: MODEL_DOWNLOAD_BYTES, message: 'AI 음성 모델을 준비하고 있어요. 처음에는 약 400MB를 내려받아요.' });
      engine = await createSpeechEngine({ loadAsset: asset => loadModelAsset(asset, id), onProgress: value => progress(id, value) });
    }
    const guide = await engine.generate(text, value => progress(id, value));
    self.postMessage({ type: 'complete', id, ...guide }, [guide.samples.buffer]);
  } catch (error) {
    const message = error instanceof Error && /[가-힣]/u.test(error.message) ? error.message
      : '이 기기에서 가이드 생성에 실패했어요. 다른 탭을 닫거나 문장을 줄여 다시 시도해 주세요.';
    self.postMessage({ type: 'error', id, message });
  } finally { busy = false; }
};
