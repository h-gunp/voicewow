// Lazy browser worker: importing this file performs no downloads or synthesis.
export function createTtsClient() {
let worker = null, pending = null, nextId = 0;
const REQUEST_TIMEOUT_MS = 6 * 60 * 1000;

function abortError() {
  const error = new Error('가이드 만들기를 취소했어요.'); error.name = 'AbortError'; return error;
}

function stopWorker() {
  if (worker) worker.terminate();
  worker = null;
}

function finish(error, value) {
  const request = pending;
  if (!request) return;
  pending = null; clearTimeout(request.timer);
  if (error) request.reject(error); else request.resolve(value);
}

/** Stop CPU/network work as well as discarding a stale result. Public immutable
 * model cache entries may survive; scripts and audio are never persisted here.
 */
function cancelGuide() {
  stopWorker();
  finish(abortError());
}

function startWorker() {
  if (worker) return worker;
  if (typeof Worker !== 'function' || typeof WebAssembly !== 'object') {
    throw new Error('이 브라우저에서는 AI 가이드를 만들 수 없어요. 최신 Safari 또는 Chrome에서 열어 주세요.');
  }
  if (globalThis.isSecureContext === false) throw new Error('AI 가이드는 보안 연결에서 사용할 수 있어요. 공개 테스트 링크로 열어 주세요.');
  try { worker = new Worker(new URL('./tts-worker.js', import.meta.url), { type: 'module', name: 'voicemate-guide' }); }
  catch { throw new Error('이 브라우저에서 음성 엔진을 시작하지 못했어요. 최신 Safari 또는 Chrome에서 열어 주세요.'); }
  const current = worker;
  current.onmessage = event => {
    if (worker !== current || !pending || event.data?.id !== pending.id) return;
    const data = event.data;
    if (data.type === 'progress') {
      // Rendering callbacks cannot interrupt generation or leave the promise open.
      try { pending.onProgress?.({ message: data.message, phase: data.phase, loaded: data.loaded, total: data.total, step: data.step, steps: data.steps }); } catch {}
    } else if (data.type === 'complete') {
      if (!(data.samples instanceof Float32Array) || !data.samples.length || !Number.isFinite(data.sampleRate) || data.sampleRate < 8000
        || data.samples.length / data.sampleRate > 20.01 || data.samples.some(value => !Number.isFinite(value))) {
        stopWorker(); finish(new Error('가이드 음성을 확인하지 못했어요. 문장을 줄여 다시 시도해 주세요.')); return;
      }
      finish(null, { samples: data.samples, sampleRate: data.sampleRate, source: data.source || 'AI 읽기 예시 · Supertonic 3' });
    } else if (data.type === 'error') {
      stopWorker(); finish(new Error(data.message || '가이드 생성에 실패했어요. 다시 시도해 주세요.'));
    }
  };
  current.onerror = event => {
    if (worker !== current) return;
    event.preventDefault?.(); stopWorker();
    finish(new Error('음성 엔진을 불러오지 못했어요. 인터넷 연결을 확인하거나 다른 탭을 닫은 뒤 다시 시도해 주세요.'));
  };
  current.onmessageerror = () => {
    if (worker !== current) return;
    stopWorker(); finish(new Error('가이드 결과를 불러오지 못했어요. 다시 시도해 주세요.'));
  };
  return worker;
}

/** Produces actual PCM samples for this sentence. It does not create a pitch
 * curve from text or claim that the generated intonation is uniquely correct.
 */
async function generateGuide(text, { onProgress } = {}) {
  if (typeof text !== 'string' || !text.trim()) throw new Error('가이드를 만들 문장을 먼저 입력해 주세요.');
  const sentence = text.trim();
  if (Array.from(sentence).length > 100) throw new Error('한 번에 100자 이하의 문장으로 가이드를 만들어 주세요.');
  if (pending) cancelGuide();
  const activeWorker = startWorker();
  const id = ++nextId;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      if (pending?.id !== id) return;
      stopWorker(); finish(new Error('가이드 준비 시간이 너무 오래 걸려 멈췄어요. 인터넷 연결을 확인하고 다시 시도해 주세요.'));
    }, REQUEST_TIMEOUT_MS);
    pending = { id, resolve, reject, timer, onProgress };
    try { activeWorker.postMessage({ type: 'generate', id, text: sentence }); }
    catch { stopWorker(); finish(new Error('음성 엔진을 시작하지 못했어요. 다시 시도해 주세요.')); }
  });
}

return { generateGuide, cancelGuide };
}
