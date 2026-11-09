import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';
import {createCaptureProcessor} from '../../apps/client/web/audio/capture-processor.mjs';

const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
};
const flush = async () => { for (let i = 0; i < 20; i++) await Promise.resolve(); };

async function browser(t, options = {}) {
  const { createRecorder } = await import('./recording.mjs');
  const { createProcessedRecorder } = await import('../../apps/client/web/audio/processed-capture.mjs');
  const workletSource = (await readFile(new URL('../../apps/client/web/audio/processed-capture-worklet.mjs', import.meta.url), 'utf8')).replace(/^import .*;$/gm, '');
  const nodes = [], contexts = [], requests = [], assetRequests = [];
  class Track extends EventTarget {
    readyState = 'live';
    stop() { this.readyState = 'ended'; }
    end() { this.readyState = 'ended'; this.dispatchEvent(new Event('ended')); }
  }
  const track = new Track();
  const stream = { getTracks: () => [track], getAudioTracks: () => [track] };
  const permission = options.permission || Promise.resolve(stream);
  class Connection {
    connected = false;
    connect() { this.connected = true; }
    disconnect() { this.connected = false; }
  }
  class Context {
    sampleRate = options.sampleRate || 48000;
    state = 'suspended';
    destination = {};
    audioWorklet = { addModule: async () => {
      if (options.moduleError) throw options.moduleError;
      if (options.moduleWait) await options.moduleWait;
    } };
    constructor(settings) { if (options.contextError) throw options.contextError; this.settings = settings; contexts.push(this); }
    createMediaStreamSource() { this.source = new Connection(); return this.source; }
    createGain() { this.mute = new Connection(); this.mute.gain = { value: 1 }; return this.mute; }
    async resume() {
      if (options.resumeError) throw options.resumeError;
      this.state = 'running';
    }
    async close() { this.state = 'closed'; }
    interrupt() { this.state = 'interrupted'; this.onstatechange?.(); }
  }
  class WorkletNode extends Connection {
    constructor(context, name, settings) {
      super();
      nodes.push(this);
      this.context = context;
      this.settings = settings;
      this.commands = [];
      this.closed = false;
      this.port = {
        onmessage: null, onmessageerror: null,
        close: () => { this.closed = true; },
        postMessage: message => {
          this.commands.push(message.type);
          if (options.ignoreFinish && message.type === 'finish') return;
          queueMicrotask(() => this.processor.port.onmessage?.({ data: message }));
        },
      };
      let Processor;
      const owner = this;
      vm.runInNewContext(workletSource, {
        Float32Array, sampleRate: context.sampleRate,
        createVoiceActivity: async () => ({ process: () => (options.decision || 'speech') === 'speech', dispose() {} }),
        createCaptureProcessor: async (wasmBinary, vad, rate, noiseReductionEnabled) => {
          if (noiseReductionEnabled === false) return createCaptureProcessor(wasmBinary, vad, rate, false);
          let pending = [], previous;
          const decision = options.decision || 'speech';
          return {
            push(samples) {
              const frames = [];
              for (const sample of samples) {
                pending.push(sample);
                if (pending.length === 480) {
                  if (previous) frames.push({samples: previous, speech: decision});
                  previous = Float32Array.from(pending); pending = [];
                }
              }
              return frames;
            },
            finish() {
              const frames = [];
              if (previous) frames.push({samples: previous, speech: decision});
              if (pending.length) frames.push({samples: Float32Array.from(pending), speech: decision});
              previous = undefined; pending = []; return frames;
            },
            dispose() { previous = undefined; pending = []; },
          };
        },
        AudioWorkletProcessor: class {
          constructor() {
            this.port = {
              onmessage: null,
              postMessage: data => queueMicrotask(() => {
                owner.port.onmessage?.({ data });
                if (data.type === 'ready') options.afterReady?.();
              }),
            };
          }
        },
        registerProcessor: (registeredName, implementation) => {
          assert.equal(registeredName, name);
          Processor = implementation;
        },
      });
      this.processor = new Processor(settings);
    }
    feed(channels) {
      const outputs = [[new Float32Array(channels[0]?.length || 128).fill(1)]];
      const active = this.processor.process([channels], outputs);
      assert.ok(outputs[0][0].every(value => value === 0), 'capture output must stay muted');
      return active;
    }
    emit(data) { this.port.onmessage?.({ data }); }
  }
  const original = new Map(['navigator', 'AudioContext', 'AudioWorkletNode', 'fetch'].map(key => [key, Object.getOwnPropertyDescriptor(globalThis, key)]));
  Object.defineProperty(globalThis, 'navigator', { configurable: true, value: { mediaDevices: {
    getUserMedia: constraints => { requests.push(constraints); return typeof permission === 'function' ? permission() : permission; },
  } } });
  globalThis.fetch = async url => { assetRequests.push(url); return {ok: true, arrayBuffer: async () => new ArrayBuffer(4)}; };
  globalThis.AudioContext = Context;
  globalThis.AudioWorkletNode = WorkletNode;
  const errors = [], limits = [];
  const recorder = (options.maxSeconds ? createProcessedRecorder : createRecorder)({ maxSeconds: options.maxSeconds, noiseReductionEnabled: options.noiseReductionEnabled, onChunk: options.onChunk, onError: error => errors.push(error), onLimit: () => limits.push(true) });
  t.after(async () => {
    await recorder.cancel();
    for (const [key, descriptor] of original) {
      if (descriptor) Object.defineProperty(globalThis, key, descriptor);
      else delete globalThis[key];
    }
  });
  return { recorder, nodes, contexts, requests, assetRequests, stream, track, errors, limits };
}

test('pronunciation always bypasses RNNoise while preserving its VAD capture contract', async t => {
  const b = await browser(t, {noiseReductionEnabled: true});
  await b.recorder.start();
  assert.deepEqual(b.assetRequests.map(url => new URL(url).pathname.split('/vendor/')[1]), ['libfvad/libfvad.wasm']);
  assert.equal(b.nodes[0].settings.processorOptions.noiseReductionEnabled, false);
  b.nodes[0].feed([Float32Array.of(.125, -.25, .5)]);
  assert.deepEqual([...(await b.recorder.stop()).samples], [.125, -.25, .5]);
});

test('only start requests the mic and stop retains the final partial mono PCM', async t => {
  const b = await browser(t);
  assert.equal(b.requests.length, 0);
  await b.recorder.start();
  assert.equal(b.requests.length, 1);
  assert.equal(b.requests[0].video, false);
  assert.equal(b.requests[0].audio.echoCancellation, false);
  assert.equal(b.requests[0].audio.noiseSuppression, false);
  assert.equal(b.requests[0].audio.autoGainControl, false);
  assert.equal(b.contexts[0].mute.gain.value, 0);
  b.nodes[0].feed([Float32Array.of(0.5, -0.5, 0.25), Float32Array.of(0.25, -0.25, 0.75)]);
  let resolved = false;
  const stopped = b.recorder.stop().then(value => { resolved = true; return value; });
  assert.equal(resolved, false, 'stop must wait for the worklet tail and final acknowledgment');
  const result = await stopped;
  assert.deepEqual([...result.samples], [0.375, -0.375, 0.5]);
  assert.equal(result.sampleRate, 48000);
  assert.equal(b.contexts[0].settings.sampleRate, 48000);
  assert.equal(b.track.readyState, 'ended');
  assert.equal(b.contexts[0].state, 'closed');
  assert.equal(b.nodes[0].closed, true);
});

test('cancel during permission prompt rejects promptly and closes a late stream', async t => {
  const permission = deferred();
  const b = await browser(t, { permission: permission.promise });
  const starting = b.recorder.start();
  const aborted = assert.rejects(starting, { name: 'AbortError' });
  await b.recorder.cancel();
  await aborted;
  permission.resolve(b.stream);
  await flush();
  assert.equal(b.track.readyState, 'ended');
  assert.equal(b.nodes.length, 0);
  assert.equal(b.errors.length, 0);
  assert.ok(b.contexts.every(context => context.state === 'closed'));
});

test('duplicate start never opens another mic and duplicate stop shares the result', async t => {
  const permission = deferred();
  const b = await browser(t, { permission: permission.promise });
  const starting = b.recorder.start();
  await assert.rejects(b.recorder.start(), /already|progress|active/i);
  permission.resolve(b.stream);
  await starting;
  await assert.rejects(b.recorder.start(), /already|progress|active/i);
  b.nodes[0].feed([Float32Array.of(0.25)]);
  const first = b.recorder.stop();
  const second = b.recorder.stop();
  assert.deepEqual(await first, await second);
  assert.equal(b.nodes[0].commands.filter(command => command === 'finish').length, 1);
  assert.equal(b.requests.length, 1);
});

test('cancel discards samples and an in-flight stop cannot resolve with stale PCM', async t => {
  const b = await browser(t, { ignoreFinish: true });
  await b.recorder.start();
  b.nodes[0].feed([new Float32Array(800).fill(0.25)]);
  await flush();
  const stopped = b.recorder.stop();
  const aborted = assert.rejects(stopped, { name: 'AbortError' });
  await b.recorder.cancel();
  await aborted;
  b.nodes[0].emit({ type: 'finished', sequence: 1, frames: 800 });
  assert.equal(b.track.readyState, 'ended');
  assert.equal(b.errors.length, 0);
});

test('10-second worklet cap truncates a crossing frame and stops even without a consumer callback', async t => {
  const b = await browser(t);
  await b.recorder.start();
  b.nodes[0].feed([new Float32Array(480017).fill(0.125)]);
  await flush();
  const result = await b.recorder.stop();
  assert.equal(result.samples.length, 480000);
  assert.equal(result.samples.at(-1), 0.125);
  assert.equal(b.limits.length, 1);
  assert.equal(b.track.readyState, 'ended');
});

test('wall deadline requests final PCM even when fewer than 10 seconds of audio arrived', async t => {
  const b = await browser(t);
  t.mock.timers.enable({ apis: ['setTimeout'] });
  await b.recorder.start();
  for (let i = 0; i < 10; i++) {
    b.nodes[0].feed([new Float32Array(4800).fill(0.125)]);
    await flush();
    t.mock.timers.tick(1000);
  }
  await flush();
  assert.equal(b.limits.length, 1);
  assert.equal((await b.recorder.stop()).samples.length, 48000);
  assert.equal(b.track.readyState, 'ended');
});

test('missing final acknowledgment fails within one second and closes the microphone', async t => {
  const b = await browser(t, { ignoreFinish: true });
  t.mock.timers.enable({ apis: ['setTimeout'] });
  await b.recorder.start();
  const stopped = b.recorder.stop();
  const rejected = assert.rejects(stopped, /final|finish|acknowledg|timed out/i);
  t.mock.timers.tick(1000);
  await rejected;
  assert.equal(b.errors.length, 1);
  assert.equal(b.track.readyState, 'ended');
});

for (const failure of ['resume', 'module']) {
  test(`${failure} setup failure closes all opened resources and rejects start`, async t => {
    const b = await browser(t, { [`${failure}Error`]: new Error(`${failure} failed`) });
    await assert.rejects(b.recorder.start(), failure === 'module' ? {captureReason: 'load_failed'} : /resume failed/);
    await flush();
    assert.equal(b.track.readyState, 'ended');
    assert.ok(b.contexts.every(context => context.state === 'closed'));
    assert.equal(b.errors.length, 0, 'start rejection reports startup errors');
  });
}

for (const failure of ['interrupted', 'ended', 'processor', 'message']) {
  test(`${failure} during capture rejects PCM and reports exactly one error`, async t => {
    const b = await browser(t);
    await b.recorder.start();
    if (failure === 'interrupted') b.contexts[0].interrupt();
    if (failure === 'ended') b.track.end();
    if (failure === 'processor') b.nodes[0].onprocessorerror?.();
    if (failure === 'message') b.nodes[0].port.onmessageerror?.();
    await assert.rejects(b.recorder.stop());
    await flush();
    assert.equal(b.errors.length, 1);
    assert.equal(b.track.readyState, 'ended');
    assert.equal(b.contexts[0].state, 'closed');
  });
}

test('missing PCM delivery is an error while actual zero-valued PCM is valid transport', async t => {
  const b = await browser(t);
  t.mock.timers.enable({ apis: ['setTimeout'] });
  await b.recorder.start();
  for (let i = 0; i < 4; i++) {
    b.nodes[0].feed([new Float32Array(4800)]);
    await flush();
    t.mock.timers.tick(1000);
  }
  assert.equal(b.errors.length, 0);
  t.mock.timers.tick(3000);
  await assert.rejects(b.recorder.stop(), /PCM|stalled|audio/i);
  assert.equal(b.errors.length, 1);
  assert.equal(b.track.readyState, 'ended');
});

test('invalid or discontinuous PCM cannot be returned for recognition', async t => {
  const b = await browser(t);
  await b.recorder.start();
  b.nodes[0].emit({ type: 'pcm', sequence: 2, startFrame: 0, sampleRate: 8000, samples: Float32Array.of(0.1) });
  await assert.rejects(b.recorder.stop(), /PCM|sequence|continu/i);
  assert.equal(b.errors.length, 1);
  assert.equal(b.track.readyState, 'ended');
});

test('worklet refuses non-finite samples', async t => {
  const b = await browser(t);
  await b.recorder.start();
  b.nodes[0].feed([Float32Array.of(NaN)]);
  await flush();
  await assert.rejects(b.recorder.stop(), /finite|audio|PCM/i);
  assert.equal(b.errors.length, 1);
});

test('cancel while loading a worklet stops the mic without waiting for addModule', async t => {
  const moduleWait = deferred();
  const b = await browser(t, { moduleWait: moduleWait.promise });
  const starting = b.recorder.start();
  const rejected = assert.rejects(starting, { name: 'AbortError' });
  await flush();
  await b.recorder.cancel();
  await rejected;
  moduleWait.resolve();
  await flush();
  assert.equal(b.track.readyState, 'ended');
  assert.equal(b.nodes.length, 0);
});

test('permission rejection never constructs a capture node and releases its audio context', async t => {
  const permission = deferred();
  const b = await browser(t, { permission: permission.promise });
  const starting = b.recorder.start();
  permission.reject(new DOMException('Permission denied', 'NotAllowedError'));
  await assert.rejects(starting, { name: 'NotAllowedError' });
  assert.equal(b.nodes.length, 0);
  assert.equal(b.contexts[0].state, 'closed');
});

test('loss of worklet input after PCM begins fails instead of returning a partial result', async t => {
  const b = await browser(t);
  await b.recorder.start();
  b.nodes[0].feed([new Float32Array(800).fill(0.1)]);
  b.nodes[0].feed([]);
  await flush();
  await assert.rejects(b.recorder.stop(), /interrupted/i);
  assert.equal(b.errors.length, 1);
});

test('cancelled permission resolving during a new recording cannot stop the new microphone', async t => {
  const first = deferred();
  let count = 0;
  let newStream;
  const b = await browser(t, { permission: () => ++count === 1 ? first.promise : Promise.resolve(newStream) });
  const newTrack = new EventTarget();
  newTrack.readyState = 'live';
  newTrack.stop = () => { newTrack.readyState = 'ended'; };
  newStream = { getTracks: () => [newTrack], getAudioTracks: () => [newTrack] };
  const staleStart = b.recorder.start();
  const rejected = assert.rejects(staleStart, { name: 'AbortError' });
  await b.recorder.cancel();
  await rejected;
  await b.recorder.start();
  first.resolve(b.stream);
  await flush();
  assert.equal(b.track.readyState, 'ended');
  assert.equal(newTrack.readyState, 'live');
  b.nodes[0].feed([Float32Array.of(0.5)]);
  assert.deepEqual([...(await b.recorder.stop()).samples], [0.5]);
  assert.equal(newTrack.readyState, 'ended');
});

test('invalid final frame count rejects the entire recording', async t => {
  const b = await browser(t, { ignoreFinish: true });
  await b.recorder.start();
  const result = b.recorder.stop();
  const rejected = assert.rejects(result, /final PCM acknowledgment/i);
  b.nodes[0].emit({ type: 'finished', sequence: 0, frames: 1 });
  await rejected;
  assert.equal(b.track.readyState, 'ended');
});

test('live consumer transfer cannot detach final PCM and the last partial arrives before stop resolves', async t => {
  const received = [], order = [];
  const b = await browser(t, {onChunk: chunk => {
    order.push('chunk');
    const owned = structuredClone(chunk.samples, {transfer: [chunk.samples.buffer]});
    received.push(...owned);
  }});
  await b.recorder.start();
  const input = Float32Array.from({length: 10007}, (_, i) => .001 * Math.sin(i));
  b.nodes[0].feed([input]);
  const result = await b.recorder.stop();
  order.push('done');
  assert.deepEqual([...result.samples], [...input]);
  assert.deepEqual(received, [...input]);
  assert.deepEqual(order, ['chunk', 'chunk', 'chunk', 'done']);
  assert.equal(result.speech.totalFrames, Math.ceil(input.length / 480));
});

test('only near-constant raw silence is rejected; VAD-negative weak PCM survives unchanged', async t => {
  const b = await browser(t, {decision: 'nonSpeech'});
  await b.recorder.start();
  b.nodes[0].feed([new Float32Array(9600)]);
  await assert.rejects(b.recorder.stop(), {captureReason: 'no_speech'});
  const track = new EventTarget();
  track.readyState = 'live'; track.stop = () => { track.readyState = 'ended'; };
  Object.defineProperty(globalThis, 'navigator', {configurable: true, value: {mediaDevices: {
    getUserMedia: async () => ({getTracks: () => [track], getAudioTracks: () => [track]}),
  }}});
  await b.recorder.start();
  const weak = Float32Array.from({length: 9600}, (_, i) => .0001 * Math.sin(i));
  b.nodes.at(-1).feed([weak]);
  const result = await b.recorder.stop();
  assert.deepEqual([...result.samples], [...weak]);
  assert.equal(result.speech.nonSpeechFrames, 20);
});

test('unsupported context rate closes its context before opening the microphone', async t => {
  const b = await browser(t, {sampleRate: 44100});
  await assert.rejects(b.recorder.start(), {captureReason: 'unsupported_sample_rate'});
  assert.equal(b.requests.length, 0);
  assert.equal(b.contexts[0].state, 'closed');
});

test('a browser rejecting the requested 48k context reports the rate-specific recovery', async t => {
  const b = await browser(t, {contextError: new DOMException('Rate unavailable', 'NotSupportedError')});
  await assert.rejects(b.recorder.start(), {captureReason: 'unsupported_sample_rate'});
  assert.equal(b.requests.length, 0);
});

test('common capture supports the twenty-second prosody cap', async t => {
  const b = await browser(t, {maxSeconds: 20});
  await b.recorder.start();
  assert.deepEqual(b.assetRequests.map(url => new URL(url).pathname.split('/vendor/')[1]), ['rnnoise/rnnoise.wasm', 'libfvad/libfvad.wasm']);
  assert.notEqual(b.nodes[0].settings.processorOptions.noiseReductionEnabled, false);
  b.nodes[0].feed([new Float32Array(960017).fill(.1)]);
  await flush();
  assert.equal((await b.recorder.stop()).samples.length, 960000);
  assert.equal(b.limits.length, 1);
});

test('a non-480-aligned cap preserves its entire final partial frame', async t => {
  const b = await browser(t, {maxSeconds: 481.1 / 48000});
  await b.recorder.start();
  const input = Float32Array.from({length: 600}, (_, i) => .1 * Math.sin(i));
  b.nodes[0].feed([input]);
  await flush();
  assert.deepEqual([...(await b.recorder.stop()).samples], [...input.slice(0, 481)]);
});

test('cancellation at the ready-node handoff closes the late node', async t => {
  let b;
  b = await browser(t, {afterReady: () => { void b.recorder.cancel(); }});
  await assert.rejects(b.recorder.start(), {name: 'AbortError'});
  await flush();
  assert.equal(b.nodes.length, 1);
  assert.equal(b.nodes[0].closed, true);
  assert.equal(b.nodes[0].connected, false);
  assert.equal(b.track.readyState, 'ended');
});
