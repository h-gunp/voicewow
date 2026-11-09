import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createNoiseProcessor} from '../../apps/client/web/audio/noise-reducer.mjs';
import {createVoiceActivity} from '../../apps/client/web/audio/voice-activity.mjs';

class Port {
  messages = []; waiters = [];
  postMessage(value, transfer = []) {
    const message = structuredClone(value, {transfer});
    this.messages.push(message);
    for (const waiter of this.waiters) if (waiter.type === message.type) waiter.resolve(message);
  }
  next(type) {
    const message = this.messages.find(value => value.type === type);
    return message ? Promise.resolve(message) : new Promise(resolve => this.waiters.push({type, resolve}));
  }
}
globalThis.sampleRate = 48000;
globalThis.AudioWorkletProcessor = class { constructor() { this.port = new Port(); } };
let Processor;
globalThis.registerProcessor = (name, type) => { assert.equal(name, 'voicemate-processed-capture'); Processor = type; };
await import('../../apps/client/web/audio/processed-capture-worklet.mjs');
const wasmBinary = await readFile(new URL('../../apps/client/web/audio/vendor/rnnoise/rnnoise.wasm', import.meta.url));
const vadBinary = await readFile(new URL('../../apps/client/web/audio/vendor/libfvad/libfvad.wasm', import.meta.url));
const create = maxSeconds => new Processor({processorOptions: {wasmBinary, vadBinary, maxSeconds}});

test('real RNNoise/VAD capture emits continuous clean PCM, metadata and final tail before acknowledgement', async () => {
  const capture = create(10);
  assert.equal((await capture.port.next('ready')).vadStatus, 'ready');
  const input = Float32Array.from({length: 12037}, (_, i) => i > 4800 && i < 9600 ? 0 : Math.sin(i * .17) * .1);
  for (let i = 0; i < input.length; i += 128) {
    const output = new Float32Array(128).fill(1);
    assert.equal(capture.process([[input.subarray(i, i + 128)]], [[output]]), true);
    assert.ok(output.every(sample => sample === 0));
  }
  capture.port.onmessage({data: {type: 'finish'}});
  const final = await capture.port.next('finished');
  const chunks = capture.port.messages.filter(value => value.type === 'pcm');
  assert.deepEqual(chunks.map(chunk => chunk.samples.length), [4800, 4800, 2437]);
  assert.deepEqual(chunks.map(chunk => chunk.startFrame), [0, 4800, 9600]);
  assert.deepEqual(chunks.map(chunk => chunk.sequence), [1, 2, 3]);
  assert.equal(capture.port.messages.at(-1).type, 'finished');
  assert.equal(final.frames, input.length);
  assert.equal(final.speech.totalFrames, Math.ceil(input.length / 480));
  assert.equal(final.speech.speechFrames + final.speech.nonSpeechFrames + final.speech.uncertainFrames, final.speech.totalFrames);
  const processor = await createNoiseProcessor(wasmBinary, await createVoiceActivity(vadBinary));
  try {
    const expected = [...processor.push(input), ...processor.finish()].flatMap(frame => [...frame.samples]);
    assert.deepEqual(chunks.flatMap(chunk => [...chunk.samples]), expected);
  } finally { processor.dispose(); }
  assert.equal(capture.process([], [[]]), false);
});

test('raw capture with VAD emits the first frame immediately and preserves every sample', async () => {
  const capture = new Processor({processorOptions: {wasmBinary: new Uint8Array([0]), vadBinary, maxSeconds: 10, noiseReductionEnabled: false}});
  const initialized = await Promise.race([capture.port.next('ready'), capture.port.next('error')]);
  assert.equal(initialized.type, 'ready', 'raw capture must not initialize the invalid RNNoise binary');
  const input = Float32Array.from({length: 12037}, (_, i) => i > 4800 && i < 9600 ? 0 : .1 * Math.sin(i * .17));
  capture.process([[input.subarray(0, 480)]], [[new Float32Array(480)]]);
  assert.equal(capture.speech.totalFrames, 1, 'the first frame must not wait for RNNoise priming');
  for (let i = 480; i < input.length; i += 128) capture.process([[input.subarray(i, i + 128)]], [[new Float32Array(128)]]);
  capture.port.onmessage({data: {type: 'finish'}});
  const final = await capture.port.next('finished');
  const actual = capture.port.messages.filter(message => message.type === 'pcm').flatMap(message => [...message.samples]);
  assert.deepEqual(actual, [...input]);
  assert.equal(final.frames, input.length);
  assert.equal(final.speech.totalFrames, 26);
  assert.equal(final.speech.uncertainFrames, 0);
  const vad = await createVoiceActivity(vadBinary);
  let speechFrames = 0;
  try {
    for (let offset = 0; offset < input.length; offset += 480) {
      const frame = new Float32Array(480);
      frame.set(input.subarray(offset, offset + 480));
      if (vad.process(frame)) speechFrames++;
    }
  } finally { vad.dispose(); }
  assert.equal(final.speech.speechFrames, speechFrames);
  assert.equal(final.speech.nonSpeechFrames, 26 - speechFrames);
  assert.equal(capture.port.messages.at(-1).type, 'finished');
});

test('pronunciation starts with invalid detector binaries and returns raw PCM with no speech metadata', async () => {
  const capture = new Processor({processorOptions: {wasmBinary: new Uint8Array([0]), vadBinary: new Uint8Array([0]), maxSeconds: 10,
    noiseReductionEnabled: false, voiceActivityEnabled: false}});
  const initialized = await Promise.race([capture.port.next('ready'), capture.port.next('error')]);
  assert.equal(initialized.type, 'ready', 'disabled detectors must not be initialized');
  assert.equal(initialized.vadStatus, undefined);
  const input = Float32Array.from({length: 10007}, (_, i) => i < 4800 ? 0 : .0001 * Math.sin(i));
  for (let i = 0; i < input.length; i += 128) capture.process([[input.subarray(i, i + 128)]], [[new Float32Array(128)]]);
  capture.port.onmessage({data: {type: 'finish'}});
  const final = await capture.port.next('finished');
  const chunks = capture.port.messages.filter(message => message.type === 'pcm');
  assert.deepEqual(chunks.flatMap(message => [...message.samples]), [...input]);
  assert.ok(chunks.every(message => message.speech === null));
  assert.equal(final.speech, null);
  assert.equal(final.frames, 10007);
  assert.equal(capture.port.messages.at(-1).type, 'finished');
});

test('shared RNNoise capture can omit VAD without inventing activity metadata', async () => {
  const capture = new Processor({processorOptions: {wasmBinary, vadBinary: new Uint8Array([0]), maxSeconds: 10, voiceActivityEnabled: false}});
  const initialized = await Promise.race([capture.port.next('ready'), capture.port.next('error')]);
  assert.equal(initialized.type, 'ready');
  const input = Float32Array.from({length: 961}, (_, i) => .1 * Math.sin(i * .17));
  capture.process([[input]], [[new Float32Array(input.length)]]);
  capture.port.onmessage({data: {type: 'finish'}});
  const final = await capture.port.next('finished');
  assert.equal(final.speech, null);
  const processor = await createNoiseProcessor(wasmBinary, null);
  try {
    const reference = [...processor.push(input), ...processor.finish()].flatMap(frame => [...frame.samples]);
    assert.deepEqual(capture.port.messages.filter(message => message.type === 'pcm').flatMap(message => [...message.samples]), reference);
  } finally { processor.dispose(); }
});

test('automatic limit flushes a partial RNNoise frame without padding duration or VAD count', async () => {
  const capture = create(961.1 / 48000);
  await capture.port.next('ready');
  assert.equal(capture.process([[new Float32Array(2000).fill(.1)]], [[new Float32Array(2000)]]), false);
  const final = await capture.port.next('finished');
  assert.equal(final.frames, 961);
  assert.equal(final.speech.totalFrames, 3);
  assert.deepEqual(capture.port.messages.slice(-3).map(value => value.type), ['pcm', 'limit', 'finished']);
  assert.equal(capture.port.messages.find(value => value.type === 'pcm').samples.length, 961);
});

test('cancel during actual asynchronous preparation never sends ready or PCM', async () => {
  const capture = create(10);
  capture.port.onmessage({data: {type: 'cancel'}});
  await new Promise(resolve => setTimeout(resolve, 20));
  assert.deepEqual(capture.port.messages, []);
  assert.equal(capture.process([[new Float32Array(128)]], [[new Float32Array(128)]]), false);
});
