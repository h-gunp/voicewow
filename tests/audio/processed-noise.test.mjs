import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import * as reducers from '../../apps/client/web/audio/noise-reducer.mjs';
import createEngine from '../../apps/client/web/audio/vendor/rnnoise/rnnoise.mjs';
import {createCaptureProcessor} from '../../apps/client/web/audio/capture-processor.mjs';

const wasmBinary = await readFile(new URL('../../apps/client/web/audio/vendor/rnnoise/rnnoise.wasm', import.meta.url));
const flatten = frames => Float32Array.from(frames.flatMap(frame => [...frame.samples]));

test('raw capture preserves frame-boundary tails, pauses and weak samples without RNNoise initialization', async () => {
  for (const length of [1, 479, 480, 481, 959, 960, 14437]) {
    const input = Float32Array.from({length}, (_, i) => i % 2000 < 1000 ? 0 : .0001 * Math.sin(i));
    let decisions = 0, disposals = 0;
    const processor = await createCaptureProcessor(new Uint8Array([0]), {
      process(frame) { assert.equal(frame.length, 480); decisions++; return false; },
      dispose() { disposals++; },
    }, 48000, false);
    const frames = [];
    for (let offset = 0; offset < input.length; offset += 128) frames.push(...processor.push(input.subarray(offset, offset + 128)));
    frames.push(...processor.finish());
    assert.deepEqual(flatten(frames), input);
    assert.equal(decisions, Math.ceil(length / 480));
    assert.ok(frames.every(frame => frame.speech === 'nonSpeech'));
    assert.deepEqual(processor.finish(), []);
    assert.throws(() => processor.push(input), /finished/);
    processor.dispose(); processor.dispose();
    assert.equal(disposals, 1);
  }
});

test('raw capture rejects invalid rates, samples and VAD results', async () => {
  await assert.rejects(createCaptureProcessor(null, {}, 44100, false), /48000/);
  const processor = await createCaptureProcessor(null, {process: () => 1, dispose() {}}, 48000, false);
  try {
    assert.throws(() => processor.push(Float32Array.of(NaN)), /finite/);
    assert.throws(() => processor.push(new Float32Array(480)), /VAD/);
  } finally { processor.dispose(); }
});

async function expected(input) {
  const engine = await createEngine({ wasmBinary });
  const state = engine._rnnoise_create(0), ptr = engine._malloc(3840), offset = ptr / 4;
  const samples = [];
  try {
    for (let frame = 0; frame <= Math.ceil(input.length / 480); frame++) {
      engine.HEAPF32.fill(0, offset, offset + 480);
      for (let i = 0; i < 480 && frame * 480 + i < input.length; i++) engine.HEAPF32[offset + i] = input[frame * 480 + i] * 32768;
      engine._rnnoise_process_frame(state, ptr + 1920, ptr);
      if (frame) for (let i = 0; i < 480; i++) samples.push(engine.HEAPF32[offset + 480 + i] / 32768);
    }
    return Float32Array.from(samples.slice(0, input.length));
  } finally { engine._rnnoise_destroy(state); engine._free(ptr); }
}

test('processed PCM preserves RNNoise delayed output and every partial tail at frame boundaries', async () => {
  assert.equal(typeof reducers.createNoiseProcessor, 'function');
  for (const length of [1, 479, 480, 481, 959, 960, 14437]) {
    let vadCalls = 0;
    const vad = { process: () => { vadCalls++; return false; }, dispose() {} };
    const processor = await reducers.createNoiseProcessor(wasmBinary, vad);
    const input = Float32Array.from({ length }, (_, i) => Math.sin(i * .2) * .1);
    const frames = [];
    try {
      for (let i = 0; i < input.length; i += 128) frames.push(...processor.push(input.subarray(i, i + 128)));
      frames.push(...processor.finish());
      assert.deepEqual(flatten(frames), await expected(input), `length ${length}`);
      assert.equal(vadCalls, Math.ceil(length / 480), 'flush padding must not become a speech-decision frame');
      assert.equal(frames.reduce((n, frame) => n + frame.samples.length, 0), length);
      assert.deepEqual(processor.finish(), []);
      assert.throws(() => processor.push(input), /finished/);
    } finally { processor.dispose(); }
  }
});

test('non-speech decisions preserve all PCM, including a long pause and weak tail', async () => {
  assert.equal(typeof reducers.createNoiseProcessor, 'function');
  const input = new Float32Array(48000);
  for (let i = 0; i < 4800; i++) input[i] = .2 * Math.sin(i * .17);
  for (let i = 40000; i < input.length; i++) input[i] = .0001 * Math.sin(i * .21);
  const processor = await reducers.createNoiseProcessor(wasmBinary, { process: () => false, dispose() {} });
  try {
    const result = [...processor.push(input), ...processor.finish()];
    assert.deepEqual(flatten(result), await expected(input));
    assert.equal(result.length, 100);
  } finally { processor.dispose(); }
});

test('processed capture rejects wrong rates and failed VAD instead of silently passing raw audio', async () => {
  assert.equal(typeof reducers.createNoiseProcessor, 'function');
  await assert.rejects(reducers.createNoiseProcessor(wasmBinary, {}, 44100), /48000/);
  const processor = await reducers.createNoiseProcessor(wasmBinary, { process() { throw new Error('VAD failed'); }, dispose() {} });
  try { assert.throws(() => processor.push(new Float32Array(960)), /VAD/); }
  finally { processor.dispose(); }
});

test('full-scale RNNoise overshoot remains valid PCM for pronunciation and replay', async () => {
  const input = Float32Array.from({length:48000}, (_, i) => Math.sin(2 * Math.PI * 220 * i / 48000) > 0 ? .99 : -.99);
  const reference = await expected(input);
  assert.ok(reference.some(sample => Math.abs(sample) > 1.001), 'fixture must reproduce the RNNoise overshoot');
  const processor = await reducers.createNoiseProcessor(wasmBinary, {process:()=>true,dispose(){}});
  try {
    const output = flatten([...processor.push(input), ...processor.finish()]);
    assert.deepEqual(output, reference.map(sample => Math.max(-1, Math.min(1, sample))));
    assert.equal(output.length, input.length);
    assert.ok(output.every(sample => Number.isFinite(sample) && Math.abs(sample) <= 1));
  } finally { processor.dispose(); }
});
