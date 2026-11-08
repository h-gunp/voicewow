import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createProsodySurface } from '../../apps/client/web/prosody/embed.js';

function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

class Element extends EventTarget {
  constructor(tagName, attributes = {}) {
    super();
    this.tagName = tagName;
    this.attributes = new Map(Object.entries(attributes));
    this.children = [];
    this.inert = false;
    this.styles = new Map();
    this.style = { setProperty: (key, value) => this.styles.set(key, value) };
    this.classes = new Set();
    this.classList = {
      add: (...values) => values.forEach(value => this.classes.add(value)),
      toggle: (value, force) => force ? this.classes.add(value) : this.classes.delete(value),
      contains: value => this.classes.has(value),
    };
  }
  set className(value) { this.classes = new Set(value.split(' ')); }
  get className() { return [...this.classes].join(' '); }
  setAttribute(key, value) { this.attributes.set(key, String(value)); }
  getAttribute(key) { return this.attributes.get(key) ?? null; }
  hasAttribute(key) { return this.attributes.has(key); }
  removeAttribute(key) { this.attributes.delete(key); }
  append(...elements) { for (const element of elements) { element.parentElement = this; this.children.push(element); } }
  remove() { if (this.parentElement) this.parentElement.children = this.parentElement.children.filter(child => child !== this); this.parentElement = null; }
  querySelectorAll(selector) {
    const all = this.children.flatMap(child => [child, ...child.querySelectorAll('*')]);
    if (selector === '*') return all;
    if (selector.includes('[href]')) return all.filter(child => child.hasAttribute('href') || child.hasAttribute('src'));
    if (selector.startsWith('#')) return all.filter(child => child.getAttribute('id') === selector.slice(1));
    return all.filter(child => child.tagName === selector);
  }
  querySelector(selector) { return this.querySelectorAll(selector)[0] ?? null; }
  getElementById(id) { return this.querySelector('#' + id); }
  cloneNode(deep) {
    const clone = new Element(this.tagName, Object.fromEntries(this.attributes));
    clone.inert = this.inert;
    if (deep) clone.append(...this.children.map(child => child.cloneNode(true)));
    return clone;
  }
}

function harness() {
  const fetched = deferred(), imported = deferred();
  const main = new Element('main', { id: 'prosody-content', 'aria-busy': 'true' });
  main.inert = true;
  main.append(new Element('button', { id: 'record' }), new Element('a', { href: './asr-notices.html' }));
  const calls = [], events = new EventTarget();
  let observer;
  const window = {
    fetch: (url, options) => { calls.push(['fetch', String(url), options.signal]); return fetched.promise; },
    DOMParser: class { parseFromString() { return { getElementById: id => id === 'prosody-content' ? main : null }; } },
    ResizeObserver: class {
      constructor(callback) { this.callback = callback; observer = this; }
      observe(target) { this.target = target; }
      disconnect() { this.disconnected = true; }
    },
  };
  const document = {
    defaultView: window,
    hidden: false,
    createElement: tag => new Element(tag),
    importNode: (node, deep) => node.cloneNode(deep),
    addEventListener: events.addEventListener.bind(events),
    removeEventListener: events.removeEventListener.bind(events),
  };
  const host = new Element('div');
  host.ownerDocument = document;
  host.height = 620;
  host.getBoundingClientRect = () => ({ width: 390, height: host.height });
  host.attachShadow = () => (host.shadowRoot = new Element('shadow-root'));
  const loadApp = () => { calls.push(['import']); return imported.promise; };
  const app = { pause: () => calls.push(['pause']), dispose: () => calls.push(['dispose']), resize: () => calls.push(['resize']) };
  const module = { createProsodyApp: options => { calls.push(['init', options]); return app; } };
  return {
    host, document, events, calls, fetched, imported, loadApp, module,
    fetchDone: () => fetched.resolve({ ok: true, text: async () => '<main id="prosody-content"></main>' }),
    cssDone: () => host.shadowRoot.querySelector('link').dispatchEvent(new Event('load')),
    get observer() { return observer; },
  };
}

const turn = () => new Promise(resolve => setImmediate(resolve));

test('ready requires the stylesheet, template, and app initialization; it scopes all DOM access', async () => {
  const ui = harness();
  const onExit = () => {};
  const surface = createProsodySurface(ui.host, onExit, { loadApp: ui.loadApp });
  let ready = false;
  surface.ready.then(() => { ready = true; });
  surface.setTextScale(1.75);
  ui.fetchDone(); ui.imported.resolve(ui.module);
  await turn();
  assert.equal(ready, false);
  assert.equal(ui.calls.some(([name]) => name === 'init'), false);
  ui.cssDone(); await surface.ready;
  const options = ui.calls.find(([name]) => name === 'init')[1];
  assert.equal(options.embedded, true);
  assert.equal(options.onExit, onExit);
  assert.equal(options.window, ui.document.defaultView);
  assert.notEqual(options.document, ui.document);
  assert.equal(options.document.documentElement, ui.host);
  assert.equal(options.document.body.classList.contains('embedded'), true);
  assert.equal(options.document.getElementById('record'), ui.host.shadowRoot.getElementById('record'));
  assert.equal(options.document.getElementById('prosody-content').inert, false);
  assert.equal(options.document.getElementById('prosody-content').hasAttribute('aria-busy'), false);
  assert.equal(ui.host.styles.get('--text-scale'), '1.75');
  assert.equal(ui.host.styles.get('--surface-height'), '620px');
  assert.match(options.document.querySelector('a').getAttribute('href'), /\/prosody\/asr-notices\.html$/);
  ui.host.shadowRoot.activeElement = options.document.getElementById('record');
  assert.equal(options.document.activeElement, ui.host.shadowRoot.activeElement);
  ui.document.hidden = true;
  assert.equal(options.document.hidden, true);
  let visibleEvents = 0;
  const listener = () => visibleEvents++;
  options.document.addEventListener('visibilitychange', listener);
  ui.events.dispatchEvent(new Event('visibilitychange'));
  options.document.removeEventListener('visibilitychange', listener);
  ui.events.dispatchEvent(new Event('visibilitychange'));
  assert.equal(visibleEvents, 1);
  surface.dispose();
});

test('disposing during lazy loading aborts fetch and blocks late initialization', async () => {
  const ui = harness();
  const surface = createProsodySurface(ui.host, () => {}, { loadApp: ui.loadApp });
  const rejected = assert.rejects(surface.ready, { name: 'AbortError' });
  const signal = ui.calls.find(([name]) => name === 'fetch')[2];
  surface.dispose(); surface.dispose();
  assert.equal(signal.aborted, true);
  ui.fetchDone(); ui.imported.resolve(ui.module);
  await rejected; await turn();
  assert.equal(ui.calls.some(([name]) => name === 'init'), false);
  assert.equal(ui.host.shadowRoot.children.length, 0);
  assert.equal(ui.observer.disconnected, true);
});

test('pause preserves the mounted DOM and disposal releases the app exactly once', async () => {
  const ui = harness();
  const surface = createProsodySurface(ui.host, () => {}, { loadApp: ui.loadApp });
  ui.fetchDone(); ui.imported.resolve(ui.module); ui.cssDone();
  await surface.ready;
  const record = ui.host.shadowRoot.getElementById('record');
  surface.pause();
  assert.equal(ui.host.shadowRoot.getElementById('record'), record);
  assert.equal(ui.calls.filter(([name]) => name === 'pause').length, 1);
  ui.host.height = 420;
  ui.observer.callback([{ target: ui.host, contentRect: { height: 420 } }]);
  assert.equal(ui.host.styles.get('--surface-height'), '420px');
  assert.equal(ui.host.shadowRoot.querySelector('div').classList.contains('small-height'), true);
  const beforeScale = ui.calls.filter(([name]) => name === 'resize').length;
  surface.setTextScale(2);
  for (const scale of [0, -1, NaN, Infinity, '2']) surface.setTextScale(scale);
  assert.equal(ui.host.styles.get('--text-scale'), '2');
  assert.equal(ui.calls.filter(([name]) => name === 'resize').length, beforeScale + 1);
  surface.dispose(); surface.dispose(); surface.pause(); surface.setTextScale(1);
  assert.equal(ui.calls.filter(([name]) => name === 'dispose').length, 1);
  assert.equal(ui.host.shadowRoot.children.length, 0);
});

test('disposing after HTML and CSS load still blocks a late cached module import', async () => {
  const ui = harness();
  const surface = createProsodySurface(ui.host, () => {}, { loadApp: ui.loadApp });
  ui.fetchDone(); ui.cssDone();
  await turn();
  const rejected = assert.rejects(surface.ready, { name: 'AbortError' });
  surface.dispose();
  ui.imported.resolve(ui.module);
  await rejected; await turn();
  assert.equal(ui.calls.some(([name]) => name === 'init'), false);
  assert.equal(ui.host.shadowRoot.children.length, 0);
});

test('remounting the same host creates fresh DOM even when the app module is cached', async () => {
  const ui = harness();
  const first = createProsodySurface(ui.host, () => {}, { loadApp: ui.loadApp });
  ui.fetchDone(); ui.imported.resolve(ui.module); ui.cssDone();
  await first.ready;
  const previousRecord = ui.host.shadowRoot.getElementById('record');
  const previousObserver = ui.observer;
  first.dispose();
  const second = createProsodySurface(ui.host, () => {}, { loadApp: ui.loadApp });
  ui.cssDone(); await second.ready;
  assert.notEqual(ui.host.shadowRoot.getElementById('record'), previousRecord);
  assert.equal(ui.calls.filter(([name]) => name === 'init').length, 2);
  const resizeCount = ui.calls.filter(([name]) => name === 'resize').length;
  previousObserver.callback([{ target: ui.host, contentRect: { height: 100 } }]);
  assert.equal(ui.calls.filter(([name]) => name === 'resize').length, resizeCount);
  assert.equal(ui.host.styles.get('--surface-height'), '620px');
  second.dispose();
  assert.equal(ui.calls.filter(([name]) => name === 'dispose').length, 2);
});

test('a stylesheet failure rejects readiness and cleans the surface', async () => {
  const ui = harness();
  const surface = createProsodySurface(ui.host, () => {}, { loadApp: ui.loadApp });
  const rejected = assert.rejects(surface.ready, /style/i);
  ui.host.shadowRoot.querySelector('link').dispatchEvent(new Event('error'));
  ui.fetchDone(); ui.imported.resolve(ui.module);
  await rejected;
  assert.equal(ui.calls.some(([name]) => name === 'init'), false);
  assert.equal(ui.host.shadowRoot.children.length, 0);
});

test('embedded typography and height do not depend on the parent document root', async () => {
  const css = await readFile(new URL('../../apps/client/web/prosody/styles.css', import.meta.url), 'utf8');
  assert.match(css, /:root,:host/);
  assert.match(css, /--text-unit:\s*calc\(16px\s*\*\s*var\(--text-scale/);
  assert.doesNotMatch(css, /\d(?:\.\d+)?rem\b/);
  assert.match(css, /height:var\(--surface-height,\s*100dvh\)/);
  assert.match(css, /\.embedded\.small-height/);
});
