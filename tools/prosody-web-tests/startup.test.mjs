import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { startProsody } from '../../apps/client/web/prosody/startup.js';

function harness(search = '?embedded=1&textScale=1.5') {
  const main = { inert: true, removeAttribute() {} };
  const status = { hidden: false, textContent: '' };
  const styles = {};
  const events = new Map(), messages = [], savedUrls = [];
  const parent = { postMessage: (data, origin) => messages.push({ data, origin }) };
  const document = {
    body: { classList: { add() {} } },
    documentElement: { style: { setProperty: (name, value) => { styles[name] = value; } } },
    getElementById: id => id === 'prosody-content' ? main : status,
  };
  const window = {
    parent,
    history: { state: null, replaceState: (_state, _title, url) => savedUrls.push(url) },
    addEventListener: (type, fn) => events.set(type, fn),
    removeEventListener: (type, fn) => { if (events.get(type) === fn) events.delete(type); },
  };
  const location = { origin: 'https://voicemate.test', search, href: `https://voicemate.test/prosody/index.html${search}` };
  return { document, window, location, main, status, styles, events, messages, parent, savedUrls };
}

test('cold startup keeps controls inert until initialization actually finishes', async () => {
  const ui = harness();
  let release;
  const pending = startProsody({ ...ui, load: () => new Promise(resolve => { release = resolve; }) });
  assert.equal(ui.main.inert, true);
  assert.equal(ui.status.hidden, false);
  assert.equal(ui.styles['--text-scale'], '1.5');
  assert.deepEqual(ui.messages, []);
  release();
  assert.equal(await pending, true);
  assert.equal(ui.main.inert, false);
  assert.equal(ui.status.hidden, true);
  assert.deepEqual(ui.messages, [{ data: { type: 'voicemate:prosody:ready' }, origin: ui.location.origin }]);
});

test('a failed import retains blocked controls and reports an actual failure', async () => {
  const ui = harness();
  assert.equal(await startProsody({ ...ui, load: async () => { throw Error('offline'); } }), false);
  assert.equal(ui.main.inert, true);
  assert.equal(ui.status.hidden, false);
  assert.match(ui.status.textContent, /다시/);
  assert.equal(ui.messages.at(-1).data.type, 'voicemate:prosody:error');
});

test('text scaling accepts only valid messages from the same-origin host and survives delayed startup', async () => {
  const ui = harness();
  let release;
  const pending = startProsody({ ...ui, load: () => new Promise(resolve => { release = resolve; }) });
  const message = ({ origin = ui.location.origin, source = ui.parent, scale = 2 } = {}) => ui.events.get('message')({ origin, source, data: { type: 'voicemate:prosody:text-scale', scale } });
  message({ origin: 'https://other.test' });
  message({ source: {} });
  for (const scale of [null, '2', NaN, Infinity, -1, 0]) message({ scale });
  assert.equal(ui.styles['--text-scale'], '1.5');
  message();
  assert.equal(ui.styles['--text-scale'], '2');
  assert.equal(new URL(ui.savedUrls.at(-1)).searchParams.get('textScale'), '2');
  release(); await pending;
  assert.equal(ui.styles['--text-scale'], '2');
  ui.events.get('pagehide')({ persisted: false });
  assert.equal(ui.events.has('message'), false);
});

test('disposing an in-flight startup prevents late readiness and releases listeners', async () => {
  const ui = harness();
  let release;
  const pending = startProsody({ ...ui, load: () => new Promise(resolve => { release = resolve; }) });
  ui.events.get('pagehide')({ persisted: false });
  release();
  assert.equal(await pending, false);
  assert.equal(ui.main.inert, true);
  assert.deepEqual(ui.messages, []);
  assert.equal(ui.events.size, 0);
});

test('initial HTML exposes preparation before loading modules and font declarations can scale', async () => {
  const html = await readFile(new URL('../../apps/client/web/prosody/index.html', import.meta.url), 'utf8');
  const css = await readFile(new URL('../../apps/client/web/prosody/styles.css', import.meta.url), 'utf8');
  assert.match(html, /id="startup-status"/);
  assert.match(html, /id="prosody-content"[^>]*inert/);
  assert.match(html, /startup\.js/);
  assert.doesNotMatch(css, /font-size:\s*\d+(?:\.\d+)?px/);
});
