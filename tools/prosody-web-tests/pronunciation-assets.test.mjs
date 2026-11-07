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

test('cache writes use pull streams instead of copying the complete model buffer', async t => {
  const BaseResponse = globalThis.Response;
  const bodies = [];
  t.mock.method(globalThis, 'Response', class extends BaseResponse {
    constructor(body, options) { super(body, options); bodies.push(body); }
  });
  t.mock.method(crypto.subtle, 'digest', () => { throw new Error('Whole-buffer digest is forbidden'); });
  const f = fixture(t);
  assert.deepEqual(await f.load(asset), bytes);
  assert.ok(bodies.at(-1) instanceof ReadableStream);
});

test('web ORT parts load sequentially from the same site and retain whole-model verification', async t => {
  const f = fixture(t);
  const calls = [];
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    calls.push({ url: String(url), options });
    return new Response(calls.length === 1 ? bytes.subarray(0,2) : bytes.subarray(2));
  });
  const model = { ...asset, path: 'ko-phone-int8.ort', partBytes: 2 };
  assert.deepEqual(await f.load(model), bytes);
  assert.ok(calls[0].url.endsWith('/pronunciation/models/ko-phone-int8.ort.part00'));
  assert.ok(calls[1].url.endsWith('/pronunciation/models/ko-phone-int8.ort.part01'));
  assert.equal(calls[0].options.body, undefined);
  assert.deepEqual(await f.load(model), bytes);
  assert.equal(calls.length, 2);
});

test('a missing web model part fails clearly without falling back to the large ONNX runtime', async t => {
  const f = fixture(t);
  t.mock.method(globalThis, 'fetch', async () => new Response('missing', { status: 404 }));
  await assert.rejects(f.load({ ...asset, path: 'ko-phone-int8.ort', partBytes: 2 }), /모델.*배포/);
  assert.equal(f.saved.length, 0);
});

test('incorrect part contents never enter the verified model cache', async t => {
  const f = fixture(t);
  t.mock.method(globalThis, 'fetch', async () => new Response(Uint8Array.of(9)));
  await assert.rejects(f.load({ ...asset, path: 'ko-phone-int8.ort', partBytes: 1 }), /해시/);
  assert.equal(f.saved.length, 0);
});
