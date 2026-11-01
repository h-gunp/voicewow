import test from 'node:test';
import assert from 'node:assert/strict';
import { createNoiseReductionNode } from '../../apps/client/web/audio/noise-reduction.mjs';

function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
async function settle() { for (let i = 0; i < 12; i++) await Promise.resolve(); }

function harness(t, { fetchGate, moduleGate, response, fetchError } = {}) {
  const nodes = [], requests = [], modules = [], timers = new Map();
  let timerId = 0;
  const context = {
    sampleRate: 48000, closes: 0,
    close() { this.closes++; },
    audioWorklet: { async addModule(url) { modules.push(url); if (moduleGate) await moduleGate.promise; } },
  };
  const values = {
    fetch: async (url, options) => {
      requests.push({url, options});
      if (fetchGate) return fetchGate.promise;
      if (fetchError) throw fetchError;
      return response ?? {ok: true, arrayBuffer: async () => new Uint8Array([0, 97, 115, 109]).buffer};
    },
    AudioWorkletNode: class {
      constructor(ctx, name, options) {
        this.context = ctx; this.name = name; this.options = options;
        this.disconnected = false; this.onprocessorerror = null;
        this.port = {
          onmessage: null, onmessageerror: null, closed: false, messages: [],
          postMessage(message) { this.messages.push(message); },
          close() { this.closed = true; },
        };
        nodes.push(this);
      }
      disconnect() { this.disconnected = true; }
    },
    setTimeout(fn, ms) { const id = ++timerId; timers.set(id, {fn, ms}); return id; },
    clearTimeout(id) { timers.delete(id); },
  };
  function replace(key, value) {
    const descriptor = Object.getOwnPropertyDescriptor(globalThis, key);
    Object.defineProperty(globalThis, key, {configurable: true, writable: true, value});
    t.after(() => { if (descriptor) Object.defineProperty(globalThis, key, descriptor); else delete globalThis[key]; });
  }
  for (const [key, value] of Object.entries(values)) replace(key, value);
  return {
    context, nodes, requests, modules, timers, replace,
    ready() { nodes.at(-1).port.onmessage?.({data: {type: 'ready'}}); },
    expire() { for (const {fn, ms} of [...timers.values()]) { assert.equal(ms, 10000); fn(); } },
  };
}

function assertDisposed(node) {
  assert.deepEqual(node.port.messages, [{type: 'dispose'}]);
  assert.equal(node.port.closed, true);
  assert.equal(node.disconnected, true);
  assert.equal(node.port.onmessage, null);
  assert.equal(node.port.onmessageerror, null);
  assert.equal(node.onprocessorerror, null);
}

for (const stage of ['response','body']) test(`stalled VAD ${stage} times out without disabling RNNoise`, async t => {
  const h=harness(t), gate=deferred(); let calls=0, vadSignal;
  h.replace('fetch', async (_url, options) => {
    if (++calls === 1) return {ok:true,arrayBuffer:async()=>new Uint8Array([0,97,115,109]).buffer};
    vadSignal=options.signal;
    return stage === 'response' ? gate.promise : {ok:true,arrayBuffer:()=>gate.promise};
  });
  const pending=createNoiseReductionNode(h.context, new AbortController().signal);
  await settle();
  const vadTimer=[...h.timers.values()].find(timer=>timer.ms === 1500);
  assert.ok(vadTimer);
  vadTimer.fn();
  await settle();
  assert.equal(vadSignal.aborted,true);
  assert.equal(h.nodes.length,1);
  assert.equal(h.nodes[0].options.processorOptions.vadBinary,null);
  h.ready();
  assert.equal(await pending,h.nodes[0]);
  assert.equal(h.nodes[0].vadStatus,'load_timeout');
  gate.resolve(stage === 'response' ? {ok:true,arrayBuffer:async()=>new ArrayBuffer(4)} : new ArrayBuffer(4));
});

test('cancelling a stalled VAD request cleans its timer and does not create a node', async t => {
  const h=harness(t), gate=deferred(), abort=new AbortController(); let calls=0, vadSignal;
  h.replace('fetch', async (_url, options) => {
    if (++calls === 1) return {ok:true,arrayBuffer:async()=>new ArrayBuffer(4)};
    vadSignal=options.signal; return gate.promise;
  });
  const pending=createNoiseReductionNode(h.context,abort.signal);
  const rejected=assert.rejects(pending,{name:'AbortError'});
  await settle(); abort.abort(); await rejected; await settle();
  assert.equal(vadSignal.aborted,true);
  assert.equal(h.timers.size,0);
  gate.resolve({ok:true,arrayBuffer:async()=>new ArrayBuffer(4)});
  await settle(); assert.equal(h.nodes.length,0);
});

test('loader_returns_only_a_ready_mono_node_and_hands_runtime_handlers_to_capture', async t => {
  const h = harness(t), abort = new AbortController();
  let resolved = false;
  const pending = createNoiseReductionNode(h.context, abort.signal).then(node => { resolved = true; return node; });
  await settle();
  assert.equal(resolved, false);
  assert.equal(h.nodes.length, 1);
  assert.equal(new URL(h.requests[0].url).pathname.endsWith('/audio/vendor/rnnoise/rnnoise.wasm'), true);
  assert.ok(h.requests[0].options.signal instanceof AbortSignal);
  assert.equal(h.requests[0].options.mode, 'same-origin');
  assert.equal(new URL(h.modules[0]).pathname.endsWith('/audio/noise-reduction-worklet.mjs'), true);
  const node = h.nodes[0];
  assert.equal(node.context, h.context);
  assert.equal(node.name, 'voicemate-noise-meter');
  assert.deepEqual(node.options, {
    numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [1],
    processorOptions: {wasmBinary: new Uint8Array([0, 97, 115, 109]), vadBinary: new Uint8Array([0, 97, 115, 109])},
  });
  h.ready();
  assert.equal(await pending, node);
  assert.equal(h.timers.size, 0);
  assert.equal(node.port.onmessage, null);
  assert.equal(node.port.onmessageerror, null);
  assert.equal(node.onprocessorerror, null);
  let runtimeEvents = 0;
  node.port.onmessage = () => runtimeEvents++;
  node.onprocessorerror = () => runtimeEvents++;
  abort.abort();
  node.port.onmessage({data: {type: 'level'}}); node.onprocessorerror();
  assert.equal(runtimeEvents, 2);
  assert.equal(node.port.closed, false);
  assert.equal(node.disconnected, false);
  assert.equal(h.context.closes, 0);
});

test('loader preserves VAD initialization status from worklet', async t => {
  const h=harness(t);
  const pending=createNoiseReductionNode(h.context, new AbortController().signal);
  await settle();
  h.nodes[0].port.onmessage({data:{type:'ready',vadStatus:'init_failed'}});
  assert.equal((await pending).vadStatus,'init_failed');
});

for (const kind of ['http', 'network', 'body']) test(`loader_${kind}_fetch_failure_rejects_without_a_node`, async t => {
  const options = kind === 'http' ? {response: {ok: false, arrayBuffer: async () => assert.fail('HTTP failure body consumed')}}
    : kind === 'network' ? {fetchError: new Error('offline')}
      : {response: {ok: true, arrayBuffer: async () => { throw new Error('interrupted body'); }}};
  const h = harness(t, options);
  await assert.rejects(createNoiseReductionNode(h.context, new AbortController().signal), {captureReason: 'load_failed'});
  assert.equal(h.nodes.length, 0);
  assert.equal(h.timers.size, 0);
  assert.equal(h.context.closes, 0);
});

for (const kind of ['message', 'processor', 'messageerror']) test(`loader_${kind}_initialization_failure_disposes_node`, async t => {
  const h = harness(t), pending = createNoiseReductionNode(h.context, new AbortController().signal);
  const rejected = assert.rejects(pending, {captureReason: 'load_failed'});
  await settle(); const node = h.nodes[0];
  if (kind === 'message') node.port.onmessage({data: {type: 'error'}});
  else if (kind === 'processor') node.onprocessorerror();
  else node.port.onmessageerror();
  await rejected;
  assertDisposed(node);
  assert.equal(h.timers.size, 0);
  assert.equal(h.context.closes, 0);
});

for (const stage of ['fetch', 'module']) test(`loader_cancelled_during_${stage}_does_not_create_a_late_node`, async t => {
  const gate = deferred(), h = harness(t, stage === 'fetch' ? {fetchGate: gate} : {moduleGate: gate});
  const abort = new AbortController(), pending = createNoiseReductionNode(h.context, abort.signal);
  const rejected = assert.rejects(pending, {name: 'AbortError'});
  await settle(); abort.abort(); await rejected;
  assert.equal(h.requests[0].options.signal.aborted, true);
  gate.resolve({ok: true, arrayBuffer: async () => new ArrayBuffer(4)}); await settle();
  assert.equal(h.nodes.length, 0);
  assert.equal(h.timers.size, 0);
  assert.equal(h.context.closes, 0);
});

test('loader_abort_while_waiting_ready_disposes_node_and_ignores_late_ready', async t => {
  const h = harness(t), abort = new AbortController();
  const pending = createNoiseReductionNode(h.context, abort.signal);
  const rejected = assert.rejects(pending, {name: 'AbortError'});
  await settle(); const node = h.nodes[0], stale = node.port.onmessage;
  abort.abort(); await rejected; stale({data: {type: 'ready'}});
  assertDisposed(node);
  assert.equal(h.timers.size, 0);
});

for (const stage of ['fetch', 'module', 'ready']) test(`loader_timeout_covers_${stage}_and_blocks_late_completion`, async t => {
  const gate = deferred(), options = stage === 'fetch' ? {fetchGate: gate} : stage === 'module' ? {moduleGate: gate} : {};
  const h = harness(t, options), pending = createNoiseReductionNode(h.context, new AbortController().signal);
  const rejected = assert.rejects(pending, {captureReason: 'load_timeout'});
  await settle(); h.expire(); await rejected;
  assert.equal(h.requests[0].options.signal.aborted, true);
  gate.resolve({ok: true, arrayBuffer: async () => new ArrayBuffer(4)}); await settle();
  if (stage === 'ready') assertDisposed(h.nodes[0]); else assert.equal(h.nodes.length, 0);
  assert.equal(h.timers.size, 0);
  assert.equal(h.context.closes, 0);
});

test('loader_rejects_unsupported_sample_rate_without_loading', async t => {
  const h = harness(t); h.context.sampleRate = 44100;
  await assert.rejects(createNoiseReductionNode(h.context, new AbortController().signal), {captureReason: 'unsupported_sample_rate'});
  assert.equal(h.requests.length, 0);
});

for (const missing of ['AudioWorkletNode', 'WebAssembly', 'audioWorklet']) test(`loader_rejects_missing_${missing}_without_loading`, async t => {
  const h = harness(t);
  if (missing === 'audioWorklet') delete h.context.audioWorklet; else h.replace(missing, undefined);
  await assert.rejects(createNoiseReductionNode(h.context, new AbortController().signal), {captureReason: 'unsupported'});
  assert.equal(h.requests.length, 0);
});

test('loader_already_aborted_signal_does_not_load_assets', async t => {
  const h = harness(t), abort = new AbortController(); abort.abort();
  await assert.rejects(createNoiseReductionNode(h.context, abort.signal), {name: 'AbortError'});
  assert.equal(h.requests.length, 0);
  assert.equal(h.timers.size, 0);
});
