import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { MODEL_ASSETS, WEB_MODEL_ASSET } from '../../apps/client/web/pronunciation/phone-engine.mjs';
import { createModelLoader } from '../../apps/client/web/pronunciation/model-loader.mjs';

const bytes = new Uint8Array(await fs.readFile(new URL('../pronunciation-spike/fixtures/ipa-vocab.json', import.meta.url)));
const asset = MODEL_ASSETS[1];

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
  assert.match(String(f.requests[0].url), /^https:\/\/huggingface\.co\/icig\/normal-korean-ipa-translation\/resolve\/772950d64427910937e11c5b76c9e4594059ce8c\/vocab.json$/);
  assert.equal(f.requests[0].options.credentials, 'omit');
  assert.equal(f.requests[0].options.body, undefined);
  assert.equal(f.saved.length, 1);
  assert.ok(f.progress.some(message => message.includes('378')));
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

for (const [name, payload] of [['short', bytes.slice(0, 2)], ['oversize', new Uint8Array(bytes.length + 1)], ['hash', new Uint8Array(bytes.length)]]) {
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

test('web graph is loaded from this deployment and reused from verified cache', async t => {
  const graph = new Uint8Array(await fs.readFile(new URL('../../apps/client/web/pronunciation/models/ko-ipa.onnx', import.meta.url)));
  const f = fixture(t, {payload: graph});
  assert.deepEqual(await f.load(WEB_MODEL_ASSET), graph);
  assert.deepEqual(f.saved, [new URL('../../apps/client/web/pronunciation/models/ko-ipa.onnx', import.meta.url).href]);
  assert.deepEqual(await f.load(WEB_MODEL_ASSET), graph);
  assert.equal(f.requests.length, 1);
  await assert.rejects(f.load({...WEB_MODEL_ASSET,path:'../secret'}), /모델 파일 정보/);
});

test('missing graph fails without a fallback model or cached partial file', async t => {
  const f = fixture(t);
  t.mock.method(globalThis, 'fetch', async () => new Response('missing', { status: 404 }));
  await assert.rejects(f.load(WEB_MODEL_ASSET), /내려받지/);
  assert.equal(f.saved.length, 0);
});

test('incorrect graph contents never enter the verified model cache', async t => {
  const f = fixture(t, {payload: new Uint8Array(WEB_MODEL_ASSET.bytes)});
  await assert.rejects(f.load(WEB_MODEL_ASSET), /해시/);
  assert.equal(f.saved.length, 0);
});
