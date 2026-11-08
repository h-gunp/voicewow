import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const html = await readFile(new URL('../../apps/client/web/index.html', import.meta.url), 'utf8');
const source = html.match(/<script type="module">([\s\S]*?)<\/script>/)[1]
  .replace(/await import\(([^)]*)\);/g, 'await load($1);');
const run = new (Object.getPrototypeOf(async function () {}).constructor)('document', 'load', source);
const errorText = '화면을 불러오지 못했다. 새로고침한다.';

function fixture() {
  const loading = { textContent: 'VoiceMate를 준비하고 있다.' };
  let script;
  const document = {
    createElement() { return {}; },
    body: { append(element) { script = element; } },
    getElementById() { return loading; },
  };
  return { document, loading, get script() { return script; } };
}

test('an asynchronous Flutter bootstrap load failure shows recovery text', async () => {
  const f = fixture();
  await run(f.document, async () => {});
  f.script.onerror?.();
  assert.equal(f.loading.textContent, errorText);
});

test('a bridge import failure shows recovery text without starting Flutter', async () => {
  const f = fixture();
  await run(f.document, async () => { throw new Error('import failed'); });
  assert.equal(f.loading.textContent, errorText);
  assert.equal(f.script, undefined);
});

test('successful imports append the Flutter bootstrap and retain loading status', async () => {
  const f = fixture(), imports = [];
  await run(f.document, async path => { imports.push(path); });
  assert.deepEqual(imports, ['./audio/capture-bridge.mjs', './pronunciation/bridge.mjs', './prosody/bridge.mjs']);
  assert.equal(f.script.src, 'flutter_bootstrap.js');
  assert.equal(f.loading.textContent, 'VoiceMate를 준비하고 있다.');
});
