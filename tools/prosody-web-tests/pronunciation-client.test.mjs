import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createPhoneClient } from '../../apps/client/web/pronunciation/client.mjs';

function fixture(t) {
  const workers = [];
  const original = globalThis.Worker;
  globalThis.Worker = class {
    constructor(url) { this.url = url; this.messages = []; workers.push(this); }
    postMessage(message) { this.messages.push(message); }
    terminate() { this.terminated = true; }
    send(type, extra = {}) { this.onmessage?.({ data: { type, id: this.messages.at(-1).id, ...extra } }); }
  };
  const client = createPhoneClient();
  t.after(() => { client.cancel(); original === undefined ? delete globalThis.Worker : globalThis.Worker = original; });
  return { client, workers };
}

test('download progress keeps preparation pending and cancellation suppresses old worker progress', async t => {
  const f = fixture(t), progress = [];
  assert.equal(f.workers.length, 0);
  const first = f.client.prepare(message => progress.push(message));
  const rejected = assert.rejects(first, { name: 'AbortError' });
  const old = f.workers[0];
  assert.match(old.url.href, /\/web\/pronunciation\/worker\.mjs$/);
  old.send('progress', { message: '356MB 다운로드다.' });
  assert.equal(f.client.ready, false);
  assert.deepEqual(progress, ['356MB 다운로드다.']);
  f.client.cancel(); await rejected;
  const second = f.client.prepare(message => progress.push(message));
  old.send('progress', { message: 'stale' }); old.send('ready');
  f.workers[1].send('ready'); await second;
  assert.deepEqual(progress, ['356MB 다운로드다.']);
  assert.equal(old.terminated, true);
});

test('download deadline rejects cleanly and allows preparation with a fresh worker', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const f = fixture(t);
  const first = f.client.prepare();
  const rejected = assert.rejects(first, /초과/);
  t.mock.timers.tick(600000);
  await rejected;
  assert.equal(f.workers[0].terminated, true);
  const second = f.client.prepare(); f.workers[1].send('ready'); await second;
  assert.equal(f.client.ready, true);
});

test('malformed phone entries cannot cross the Dart result boundary', async t => {
  const f = fixture(t);
  const prepared = f.client.prepare(); f.workers[0].send('ready'); await prepared;
  const result = f.client.recognize(new Float32Array(3200).fill(.1), 16000);
  f.workers[0].send('result', { result: { phones: [{ phone: 7 }], display: { text: '', segments: [] }, inferenceMs: 1, duration: .2 } });
  await assert.rejects(result, /결과/);
  assert.equal(f.workers[0].terminated, true);
});

test('product bootstrap imports the inert bridge before Flutter and tools reexport product PCM', async () => {
  const root = new URL('../../', import.meta.url);
  const index = await readFile(new URL('apps/client/web/index.html', root), 'utf8');
  assert.ok(index.indexOf("import('./pronunciation/bridge.mjs')") < index.indexOf("bootstrap.src='flutter_bootstrap.js'"));
  for (const file of ['audio', 'phones', 'phone-engine', 'recording']) {
    assert.equal((await readFile(new URL(`tools/pronunciation-spike/${file}.mjs`, root), 'utf8')).trim(),
      `export * from '../../apps/client/web/pronunciation/${file}.mjs';`);
  }
});
