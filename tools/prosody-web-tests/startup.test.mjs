import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { startProsody } from '../../apps/client/web/prosody/startup.js';

function harness() {
  const main = { inert: true, removeAttribute() {} };
  const status = { hidden: false, textContent: '' };
  const events = new Map(), calls = [];
  const document = { getElementById: id => id === 'prosody-content' ? main : status };
  const window = {
    addEventListener: (type, fn) => events.set(type, fn),
    removeEventListener: (type, fn) => { if (events.get(type) === fn) events.delete(type); },
  };
  const module = { createProsodyApp: options => calls.push(options) };
  return { document, window, main, status, events, calls, module };
}

test('standalone startup explicitly mounts the factory before releasing inert controls', async () => {
  const ui = harness();
  let release;
  const pending = startProsody({ ...ui, load: () => new Promise(resolve => { release = resolve; }) });
  assert.equal(ui.main.inert, true);
  assert.equal(ui.status.hidden, false);
  assert.equal(ui.calls.length, 0);
  release(ui.module);
  assert.equal(await pending, true);
  assert.equal(ui.main.inert, false);
  assert.equal(ui.status.hidden, true);
  assert.deepEqual(ui.calls, [{ document: ui.document, window: ui.window }]);
  assert.equal(ui.events.size, 0);
});

test('import or factory failures keep blocked controls and a visible failure', async () => {
  for (const load of [async () => { throw Error('offline'); }, async () => ({ createProsodyApp() { throw Error('initialization'); } })]) {
    const ui = harness();
    assert.equal(await startProsody({ ...ui, load }), false);
    assert.equal(ui.main.inert, true);
    assert.equal(ui.status.hidden, false);
    assert.match(ui.status.textContent, /다시/);
    assert.equal(ui.events.size, 0);
  }
});

test('leaving during startup cannot mount a late module', async () => {
  const ui = harness();
  let release;
  const pending = startProsody({ ...ui, load: () => new Promise(resolve => { release = resolve; }) });
  ui.events.get('pagehide')({ persisted: false });
  release(ui.module);
  assert.equal(await pending, false);
  assert.equal(ui.main.inert, true);
  assert.equal(ui.calls.length, 0);
  assert.equal(ui.events.size, 0);
});

test('initial standalone HTML keeps its preparation and explicit startup entry', async () => {
  const html = await readFile(new URL('../../apps/client/web/prosody/index.html', import.meta.url), 'utf8');
  assert.match(html, /id="startup-status"/);
  assert.match(html, /id="prosody-content"[^>]*inert/);
  assert.match(html, /startup\.js/);
});
