// Sequential orchestration only. Importing this module creates no worker,
// downloads no model and performs no synthesis.
const ABORTED = Symbol('guide-batch-aborted');

function isAbort(error) {
  return error?.name === 'AbortError';
}

// Observe the generation promise even after cancellation so a late rejection
// cannot become unhandled. Physical worker cancellation belongs to the caller.
function generateUntilAbort(start, signal) {
  if (signal?.aborted) return Promise.resolve(ABORTED);
  return new Promise((resolve, reject) => {
    let finished = false;
    const remove = () => signal?.removeEventListener('abort', abort);
    const abort = () => {
      if (finished) return;
      finished = true; remove(); resolve(ABORTED);
    };
    signal?.addEventListener('abort', abort, { once: true });
    Promise.resolve().then(() => signal?.aborted ? ABORTED : start()).then(value => {
      if (finished) return;
      finished = true; remove(); resolve(value);
    }, error => {
      if (finished) return;
      finished = true; remove(); reject(error);
    });
  });
}

/** Prepare a queue with one generation in flight at a time.
 *
 * hasGuide(item) includes both generated guides and user-supplied references.
 * commit(item, value) must synchronously store the prepared guide; keeping that
 * small operation in the same turn as the abort check prevents stale saves.
 * The caller owns the cache, generated values and actual worker cancellation.
 * A failed item does not discard earlier guides or stop subsequent items.
 *
 * total = ready + failed + remaining. On cancellation, the interrupted item
 * and every unstarted item remain in `remaining`, not in `failed`.
 */
export async function runGuideBatch({
  items,
  hasGuide = () => false,
  generate,
  commit,
  onUpdate,
  signal,
} = {}) {
  if (!Array.isArray(items)) throw new TypeError('가이드를 준비할 문장 목록이 필요해요.');
  if (typeof hasGuide !== 'function' || typeof generate !== 'function' || typeof commit !== 'function') {
    throw new TypeError('가이드 확인·생성·저장 방법을 연결해 주세요.');
  }
  const queue = items.slice(), failures = [], readyIndices = new Set();
  let cancelled = false, closed = false, phase = 'preparing', currentIndex = null, progress = null;

  function snapshot() {
    return {
      total: queue.length,
      ready: readyIndices.size,
      failed: failures.length,
      remaining: queue.length - readyIndices.size - failures.length,
      cancelled,
      failures: failures.map(failure => ({ ...failure })),
      phase,
      currentIndex,
      currentItem: currentIndex === null ? null : queue[currentIndex],
      progress,
    };
  }
  function notify() {
    // Rendering or analytics failures must not break generation or cache saves.
    try { onUpdate?.(snapshot()); } catch {}
  }
  function failure(index, error) {
    failures.push({ id: queue[index]?.id, index, text: queue[index]?.text,
      message: error?.message || String(error || '가이드를 준비하지 못했어요.') });
  }

  // Count the cache before starting so progress includes already-ready guides.
  const missing = [];
  for (let index = 0; index < queue.length; index++) {
    if (signal?.aborted) { cancelled = true; break; }
    try {
      if (hasGuide(queue[index])) readyIndices.add(index);
      else missing.push(index);
    } catch (error) {
      if (isAbort(error) || signal?.aborted) { cancelled = true; break; }
      failure(index, error);
    }
  }
  notify();

  for (const index of missing) {
    if (cancelled || signal?.aborted) { cancelled = true; break; }
    const item = queue[index];
    try {
      // A guide may have become available since the initial cache count.
      if (hasGuide(item)) {
        readyIndices.add(index); notify(); continue;
      }
      currentIndex = index; progress = null; phase = 'generating'; notify();
      const value = await generateUntilAbort(() => generate(item, {
        onProgress: next => {
          if (closed || cancelled || signal?.aborted || phase !== 'generating' || currentIndex !== index) return;
          progress = next; notify();
        },
      }), signal);
      if (value === ABORTED || signal?.aborted) { cancelled = true; break; }
      // No await between this cancellation check and the atomic cache change.
      const saved = commit(item, value);
      if (saved && typeof saved.then === 'function') {
        // Observe rejection even though asynchronous cache writes are not a
        // supported transaction for this browser-local orchestration helper.
        Promise.resolve(saved).catch(() => {});
        throw new TypeError('가이드 저장은 한 번에 완료되는 동기 작업이어야 해요.');
      }
      readyIndices.add(index); phase = 'ready'; progress = null; notify();
    } catch (error) {
      if (isAbort(error) || signal?.aborted) { cancelled = true; break; }
      failure(index, error); phase = 'failed'; progress = null; notify();
    }
  }
  if (signal?.aborted) cancelled = true;
  closed = true; currentIndex = null; progress = null;
  phase = cancelled ? 'cancelled' : 'complete';
  notify();
  return snapshot();
}
