import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createModelLoader } from '../../apps/client/web/pronunciation/model-loader.mjs';

const bytes = Uint8Array.of(1, 2, 3);
const asset = { path: 'vocab.json', bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') };

function fixture(t, { cached, payload = bytes, cacheFails = false, headers } = {}) {
  const requests = [], progress = [], removed = [], saved = [];
  let value = cached;
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    requests.push({ url, options });
    return new Response(payload, { headers });
  });
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, 'caches');
  Object.defineProperty(globalThis, 'caches', { configurable: true, value: { open: async () => {
    if (cacheFails) throw new Error('quota');
    return {
      match: async () => value && new Response(value),
      delete: async url => { removed.push(url); value = undefined; },
      put: async (url, response) => { saved.push(url); value = new Uint8Array(await response.arrayBuffer()); },
    };
  } } });
  t.after(() => descriptor ? Object.defineProperty(globalThis, 'caches', descriptor) : delete globalThis.caches);
  return { load: createModelLoader(message => progress.push(message)), requests, progress, removed, saved };
}

test('fixed revision download validates and caches bytes, with no audio request body', async t => {
  const f = fixture(t);
  assert.deepEqual(await f.load(asset), bytes);
  assert.equal(f.requests.length, 1);
  assert.match(String(f.requests[0].url), /^https:\/\/huggingface\.co\/chegrowk\/ko-phone-int8\/resolve\/dbb9c196f3e5e72d41c8ce2b63e6d0c91a011b70\/vocab.json$/);
  assert.equal(f.requests[0].options.credentials, 'omit');
  assert.equal(f.requests[0].options.body, undefined);
  assert.equal(f.saved.length, 1);
  assert.ok(f.progress.some(message => message.includes('356')));
  assert.deepEqual(await f.load(asset), bytes);
  assert.equal(f.requests.length, 1);
  assert.ok(f.progress.some(message => message.includes('캐시')));
});

test('corrupt cached bytes are removed and replaced only with verified download', async t => {
  const f = fixture(t, { cached: Uint8Array.of(9, 9, 9) });
  assert.deepEqual(await f.load(asset), bytes);
  assert.equal(f.removed.length, 1);
  assert.equal(f.saved.length, 1);
});

for (const [name, payload] of [['short', bytes.slice(0, 2)], ['oversize', Uint8Array.of(1, 2, 3, 4)], ['hash', Uint8Array.of(3, 2, 1)]]) {
  test(`${name} download is rejected without saving a cache entry`, async t => {
    const f = fixture(t, { payload });
    await assert.rejects(f.load(asset), /크기|해시/);
    assert.equal(f.saved.length, 0);
  });
}

test('unavailable cache does not block verified local inference', async t => {
  const f = fixture(t, { cacheFails: true });
  assert.deepEqual(await f.load(asset), bytes);
  assert.ok(f.progress.some(message => message.includes('캐시')));
});

test('transfer Content-Length does not override validated decompressed artifact size', async t => {
  const f = fixture(t, { headers: { 'Content-Length': '23', 'Content-Encoding': 'gzip' } });
  assert.deepEqual(await f.load(asset), bytes);
  assert.equal(f.saved.length, 1);
});
