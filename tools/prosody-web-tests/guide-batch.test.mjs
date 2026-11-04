import test from 'node:test';
import assert from 'node:assert/strict';
import { runGuideBatch } from '../../apps/client/web/prosody/guide-batch.js';

const items = [{ id: 0, text: '안녕하세요.' }, { id: 1, text: '오늘도 연습해요.' }, { id: 2, text: '감사합니다.' }];
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
};
const tick = () => new Promise(resolve => setImmediate(resolve));

test('one batch generates sequentially and publishes completed guides before starting the next item', async () => {
  const cache = new Map(), calls = [], pending = [], updates = [];
  let active = 0, peak = 0;
  const batch = runGuideBatch({ items, hasGuide: item => cache.has(item.id),
    generate(item, { onProgress }) {
      calls.push(item.id); active++; peak = Math.max(peak, active);
      onProgress({ message: '준비 중', step: 1 });
      const d = deferred(); pending.push(d);
      return d.promise.finally(() => active--);
    },
    commit(item, value) { cache.set(item.id, value); }, onUpdate: value => updates.push(value) });
  await tick(); assert.deepEqual(calls, [0]);
  pending[0].resolve('first'); await tick();
  assert.deepEqual(calls, [0, 1]); assert.equal(cache.get(0), 'first');
  pending[1].resolve('second'); await tick();
  assert.deepEqual(calls, [0, 1, 2]);
  pending[2].resolve('third');
  const result = await batch;
  assert.equal(peak, 1);
  assert.deepEqual([result.total, result.ready, result.failed, result.remaining, result.cancelled], [3, 3, 0, 0, false]);
  assert.equal(result.phase, 'complete');
  assert.ok(updates.some(value => value.currentIndex === 0 && value.progress?.message === '준비 중'));
  assert.ok(updates.some(value => value.ready === 1 && value.currentIndex === 0));
});

test('cached generated or uploaded guides are reused, and retry generates only previously failed items', async () => {
  const uploaded = { name: 'user-reference.wav' }, cache = new Map([[0, uploaded]]), calls = [];
  let fail = true;
  const options = { items, hasGuide: item => cache.has(item.id),
    async generate(item) { calls.push(item.id); if (item.id === 1 && fail) throw new Error('이 문장만 실패'); return item.text; },
    commit(item, value) { cache.set(item.id, value); } };
  const first = await runGuideBatch(options);
  assert.deepEqual(calls, [1, 2]); assert.equal(cache.get(0), uploaded);
  assert.deepEqual([first.ready, first.failed, first.remaining], [2, 1, 0]);
  assert.deepEqual(first.failures, [{ id: 1, index: 1, text: items[1].text, message: '이 문장만 실패' }]);
  fail = false; calls.length = 0;
  const retry = await runGuideBatch(options);
  assert.deepEqual(calls, [1]);
  assert.deepEqual([retry.ready, retry.failed, retry.remaining], [3, 0, 0]);
});

test('cancelling a pending generation returns promptly and ignores late audio and progress without losing completed guides', async () => {
  const controller = new AbortController(), cache = new Map(), updates = [];
  let lateProgress, pending;
  const batch = runGuideBatch({ items, signal: controller.signal, hasGuide: item => cache.has(item.id),
    generate(item, { onProgress }) {
      if (item.id === 0) return 'ready';
      lateProgress = onProgress; pending = deferred(); return pending.promise;
    }, commit(item, value) { cache.set(item.id, value); }, onUpdate: value => updates.push(value) });
  await tick(); controller.abort();
  const result = await batch;
  assert.deepEqual([result.ready, result.failed, result.remaining, result.cancelled], [1, 0, 2, true]);
  assert.equal(cache.get(0), 'ready'); assert.equal(cache.has(1), false);
  const count = updates.length;
  lateProgress({ message: 'late' }); pending.resolve('late audio'); await tick();
  assert.equal(cache.has(1), false); assert.equal(cache.has(2), false); assert.equal(updates.length, count);
});

test('late generation rejection after cancellation is observed rather than becoming a failed guide', async () => {
  const controller = new AbortController(), pending = deferred();
  const batch = runGuideBatch({ items, signal: controller.signal, generate: () => pending.promise, commit() { assert.fail('cancelled result cannot commit'); } });
  await tick(); controller.abort();
  const result = await batch;
  pending.reject(new Error('late rejection')); await tick();
  assert.equal(result.failed, 0); assert.equal(result.remaining, 3); assert.equal(result.cancelled, true);
});

test('AbortError stops the queue without counting the interrupted sentence as a synthesis failure', async () => {
  const calls = [];
  const result = await runGuideBatch({ items, generate(item) { calls.push(item.id); const error = new Error('멈춤'); error.name = 'AbortError'; throw error; }, commit() { assert.fail('no generated audio'); } });
  assert.deepEqual(calls, [0]);
  assert.deepEqual([result.ready, result.failed, result.remaining, result.cancelled], [0, 0, 3, true]);
});

test('rendering callback errors do not prevent generation or cache saves, and snapshots do not share failure arrays', async () => {
  const cache = new Map();
  const result = await runGuideBatch({ items, generate: item => item.text, commit(item, value) { cache.set(item.id, value); },
    onUpdate(snapshot) { snapshot.failures.push({ message: 'UI mutation' }); throw new Error('UI failed'); } });
  assert.equal(cache.size, 3); assert.equal(result.ready, 3); assert.deepEqual(result.failures, []);
});

test('empty, already cached or already cancelled batches do not generate audio', async () => {
  const generate = () => assert.fail('no synthesis should start');
  const empty = await runGuideBatch({ items: [], generate, commit() {} });
  assert.deepEqual([empty.total, empty.ready, empty.remaining], [0, 0, 0]);
  const cached = await runGuideBatch({ items, hasGuide: () => true, generate, commit() {} });
  assert.equal(cached.ready, 3);
  const controller = new AbortController(); controller.abort();
  const cancelled = await runGuideBatch({ items, signal: controller.signal, generate, commit() {} });
  assert.equal(cancelled.cancelled, true); assert.equal(cancelled.remaining, 3);
});

test('cancellation from a progress/render callback cannot start or save an unwanted next item', async () => {
  const controller = new AbortController(), calls = [], committed = [];
  const result = await runGuideBatch({ items, signal: controller.signal,
    generate(item, { onProgress }) { calls.push(item.id); onProgress('progress'); return 'audio'; },
    commit(item) { committed.push(item.id); },
    onUpdate(snapshot) { if (snapshot.progress) controller.abort(); } });
  assert.deepEqual(calls, [0]); assert.deepEqual(committed, []);
  assert.equal(result.cancelled, true); assert.equal(result.remaining, 3);
});
