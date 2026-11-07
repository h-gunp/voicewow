import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { patchRuntime } from '../pronunciation-spike/patch-runtime.mjs';

const runtimeUrl = new URL('../../apps/client/web/pronunciation/vendor/onnx/ort.wasm.min.mjs', import.meta.url);
const source = readFileSync(runtimeUrl, 'utf8');

test('runtime patch is identical for LF and Windows CRLF checkouts', () => {
  const upstream = readFileSync(new URL('../../apps/client/web/prosody/vendor/onnx/ort.wasm.min.mjs', import.meta.url), 'utf8');
  const lf = upstream.replace(/\r\n/g, '\n');
  assert.equal(patchRuntime(lf), patchRuntime(lf.replace(/\n/g, '\r\n')));
});

// Exercise the shipped create/release functions; the native WASM API is the unavoidable test boundary.
function runtime({ createFails = false, metadataFails = false, releaseFails = false, cleanupFails = false, optionsCleanupFails = false, unmountFails = false, beforeCreate = () => {} } = {}) {
  const sessions = new Map(), retained = new Map(), events = [], copied = [];
  let nextSession = 100, nextPointer = 1000;
  const wasm = {
    HEAPU8: new Uint8Array(1),
    _OrtCreateSession: async () => { beforeCreate(); return createFails ? 0 : nextSession++; },
    _OrtReleaseSession: handle => { events.push(['release', handle]); return releaseFails ? 1 : 0; },
    _OrtReleaseSessionOptions: () => optionsCleanupFails ? 1 : 0,
    _OrtFree: () => 0,
    _free: pointer => events.push(['free', pointer]),
    UTF8ToString: () => 'input',
    jsepOnReleaseSession: () => { if (cleanupFails) throw new Error('cleanup failed'); },
    unmountExternalData: () => { if (unmountFails) throw new Error('unmount failed'); },
  };
  const begin = source.indexOf('Pe=async(e,t)=>'), end = source.indexOf(',dn=async', begin);
  assert.ok(begin >= 0 && end > begin, 'Pinned runtime create/release boundaries exist');
  const createFunctions = new Function('I', 'me', 'on', 'T', 'jn', 'cn', 'ae', 'pronunciationModelBuffers',
    `let Pe, De; ${source.slice(begin, end)}; return { create: Pe, release: De };`);
  const api = createFunctions(() => wasm, input => { copied.push(new Uint8Array(input)); return [nextPointer++, input.byteLength]; }, async () => [1, []],
    message => { throw new Error(message); }, () => { if (metadataFails) throw new Error('metadata failed'); return [1, 0]; },
    () => [10, 0], sessions, retained);
  return { ...api, sessions, retained, events, copied };
}

const direct = { executionProviders: ['wasm'], extra: { session: { use_ort_model_bytes_for_initializers: '1' } } };
const consume = { executionProviders: ['wasm'], extra: { session: { use_ort_model_bytes_for_initializers: '1', voicemate_consume_model_bytes: '1' } } };
const model = new Uint8Array(10);

test('direct initializers retain model bytes until native session release', async () => {
  const r = runtime();
  const [session] = await r.create(model, direct);
  assert.deepEqual(r.events, []);
  assert.equal(r.retained.size, 1);
  r.release(session);
  assert.deepEqual(r.events, [['release', session], ['free', 1000]]);
  assert.equal(r.retained.size, 0);
  assert.equal(r.sessions.size, 0);
  assert.throws(() => r.release(session), /invalid session/);
  assert.equal(r.events.filter(x => x[0] === 'free').length, 1);
});

test('ordinary model sessions retain the original immediate-free behavior', async () => {
  const r = runtime();
  const [session] = await r.create(model, { executionProviders: ['wasm'] });
  assert.deepEqual(r.events, [['free', 1000]]);
  assert.equal(r.retained.size, 0);
  r.release(session);
  assert.deepEqual(r.events, [['free', 1000], ['release', session]]);
});

for (const failure of ['createFails', 'metadataFails', 'optionsCleanupFails', 'unmountFails']) {
  test(`failed creation (${failure}) frees bytes without retaining a session`, async () => {
    const r = runtime({ [failure]: true });
    await assert.rejects(r.create(model, direct));
    assert.equal(r.retained.size, 0);
    assert.equal(r.sessions.size, 0);
    assert.deepEqual(r.events.filter(x => x[0] === 'free'), [['free', 1000]]);
    assert.equal(r.events.filter(x => x[0] === 'release').length, failure === 'createFails' ? 0 : 1);
  });
}

for (const failure of ['releaseFails', 'cleanupFails']) {
  test(`release failure (${failure}) still releases the session and model bytes once`, async () => {
    const r = runtime({ [failure]: true });
    const [session] = await r.create(model, direct);
    assert.throws(() => r.release(session));
    assert.deepEqual(r.events, [['release', session], ['free', 1000]]);
    assert.equal(r.retained.size, 0);
    assert.equal(r.sessions.size, 0);
    assert.throws(() => r.release(session), /invalid session/);
    assert.equal(r.events.filter(x => x[0] === 'free').length, 1);
  });
}

test('independent sessions release only their own retained model bytes', async () => {
  const r = runtime();
  const [first] = await r.create(model, direct), [second] = await r.create(model, direct);
  r.release(first);
  assert.equal(r.retained.size, 1);
  assert.equal(r.retained.get(second), 1001);
  r.release(second);
  assert.deepEqual(r.events, [['release', first], ['free', 1000], ['release', second], ['free', 1001]]);
  assert.equal(r.retained.size, 0);
});

test('runtime artifact is reproducible and an unexpected upstream is rejected', () => {
  const upstream = readFileSync(new URL('../../apps/client/web/prosody/vendor/onnx/ort.wasm.min.mjs', import.meta.url), 'utf8');
  assert.equal(patchRuntime(upstream), source);
  assert.throws(() => patchRuntime(upstream + '\n'), /Unexpected upstream/);
  assert.doesNotMatch(source, /__mobileProbeLifetime|__mobileHeldModels/);
});

test('pronunciation runtime exposes exactly the upstream public exports', async () => {
  const patched = await import(runtimeUrl.href);
  const upstream = await import('../../apps/client/web/prosody/vendor/onnx/ort.wasm.min.mjs');
  assert.deepEqual(Object.keys(patched), Object.keys(upstream));
});

test('explicitly owned full input is consumed only after the bytes are copied to WASM', async () => {
  const bytes = Uint8Array.from([3, 1, 4]);
  const r = runtime({ beforeCreate: () => assert.equal(bytes.byteLength, 0) });
  const [session] = await r.create(bytes, consume);
  assert.deepEqual(r.copied[0], Uint8Array.from([3, 1, 4]));
  r.release(session);
});

test('borrowed input stays usable unless both direct initializers and ownership flags are set', async () => {
  for (const options of [direct, { extra: { session: { voicemate_consume_model_bytes: '1' } } }]) {
    const bytes = Uint8Array.from([3, 1, 4]), r = runtime();
    const [session] = await r.create(bytes, options);
    assert.deepEqual(bytes, Uint8Array.from([3, 1, 4]));
    r.release(session);
  }
});

test('subarray and shared inputs are never detached', async () => {
  for (const bytes of [new Uint8Array(10).subarray(1), new Uint8Array(new SharedArrayBuffer(10))]) {
    const length = bytes.byteLength, r = runtime();
    const [session] = await r.create(bytes, consume);
    assert.equal(bytes.byteLength, length);
    r.release(session);
  }
});

test('missing or rejected ArrayBuffer transfer falls back to the borrowed input path', async () => {
  for (const transfer of [undefined, () => { throw new TypeError('not transferable'); }]) {
    const bytes = new Uint8Array(10), r = runtime();
    Object.defineProperty(bytes.buffer, 'transfer', { value: transfer });
    const [session] = await r.create(bytes, consume);
    assert.equal(bytes.byteLength, 10);
    r.release(session);
  }
});

test('failed creation after consuming owned input frees the WASM copy once', async () => {
  const bytes = new Uint8Array(10), r = runtime({ createFails: true });
  await assert.rejects(r.create(bytes, consume));
  assert.equal(bytes.byteLength, 0);
  assert.deepEqual(r.events, [['free', 1000]]);
  assert.equal(r.retained.size, 0);
  assert.equal(r.sessions.size, 0);
});
