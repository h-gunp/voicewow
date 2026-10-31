import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createNoiseMeter } from '../../apps/client/web/audio/noise-reducer.mjs';
import createRNNWasmModule from '../../apps/client/web/audio/vendor/rnnoise/rnnoise.mjs';

const wasmBinary = await readFile(new URL('../../apps/client/web/audio/vendor/rnnoise/rnnoise.wasm', import.meta.url));

test('bundled RNNoise output places the test signal predominantly in the next frame', async () => {
  const engine = await createRNNWasmModule({wasmBinary});
  const state = engine._rnnoise_create(0), ptr = engine._malloc(3840), offset = ptr/4;
  const energies = [];
  try {
    for (let frame=0;frame<3;frame++) {
      for (let i=0;i<480;i++) engine.HEAPF32[offset+i] = frame === 0 ? Math.sin(i*.2)*15000 : 0;
      engine._rnnoise_process_frame(state,ptr+1920,ptr);
      let energy=0;
      for (let i=0;i<480;i++) energy += engine.HEAPF32[offset+480+i] ** 2;
      energies.push(energy);
    }
    assert.ok(energies[1] > energies[0] * 100);
    assert.ok(energies[1] > energies[2] * 10);
  } finally { engine._rnnoise_destroy(state); engine._free(ptr); }
});

test('analysis aligns previous raw frame with delayed RNNoise output', async () => {
  const frames = [];
  const vad = {process: () => false};
  const meter = await createNoiseMeter(wasmBinary, 48000, {vad, onAnalysis: f => frames.push(f)});
  try {
    meter.push(new Float32Array(480).fill(.25));
    assert.equal(frames.length, 0);
    meter.push(new Float32Array(480).fill(.5));
    assert.equal(frames.length, 1);
    assert.equal(frames[0].seq, 0);
    assert.equal(frames[0].power, .0625);
    assert.equal(frames[0].sampleStart, 0);
  } finally { meter.dispose(); }
});

test('real_rnnoise_keeps_silence_at_zero_and_emits_complete_100ms_windows', async () => {
  const meter = await createNoiseMeter(wasmBinary, 48000);
  try {
    assert.deepEqual(meter.push(new Float32Array(4799)), []);
    const frames = meter.push(new Float32Array(1));
    assert.equal(frames.length, 1);
    assert.deepEqual(frames[0], {rms:0, peak:0, dbfs:null, normalized:0, sampleCount:4800});
  } finally { meter.dispose(); }
});

test('different_input_block_boundaries_produce_the_same_processed_measurements', async () => {
  const a = await createNoiseMeter(wasmBinary, 48000);
  const b = await createNoiseMeter(wasmBinary, 48000);
  const input = Float32Array.from({length:14437}, (_, i) => .1 * Math.sin(i * .13));
  try {
    const whole = a.push(input), blocked = [];
    for (let i=0; i<input.length; i+=128) blocked.push(...b.push(input.subarray(i,i+128)));
    assert.equal(whole.length, 3);
    assert.deepEqual(blocked, whole);
  } finally { a.dispose(); b.dispose(); }
});

test('real_rnnoise_reduces_stationary_noise_after_warmup', async () => {
  const meter = await createNoiseMeter(wasmBinary, 48000);
  let seed = 123456789, inputEnergy = 0;
  const samples = Float32Array.from({length:48000*3}, () => {
    seed = (Math.imul(seed,1664525) + 1013904223) >>> 0;
    const sample = (seed / 4294967296 - .5) * .1;
    inputEnergy += sample * sample;
    return sample;
  });
  try {
    const stableFrames = meter.push(samples).slice(10);
    const inputRms = Math.sqrt(inputEnergy/samples.length);
    const outputRms = Math.sqrt(stableFrames.reduce((sum,f)=>sum+f.rms*f.rms,0)/stableFrames.length);
    assert.equal(stableFrames.length, 20);
    assert.ok(outputRms < inputRms*.5, `Noise was not reduced: ${inputRms} -> ${outputRms}`);
    assert.ok(stableFrames.every(f=>Number.isFinite(f.rms) && Number.isFinite(f.peak)));
  } finally { meter.dispose(); }
});

test('unsupported_sample_rate_is_rejected_instead_of_processing_at_the_wrong_speed', async () => {
  await assert.rejects(createNoiseMeter(wasmBinary, 44100), /48000/);
});

test('nonfinite_audio_and_processing_after_disposal_are_rejected', async () => {
  const meter = await createNoiseMeter(wasmBinary, 48000);
  try { assert.throws(()=>meter.push(new Float32Array([NaN])), /finite/); }
  finally { meter.dispose(); }
  meter.dispose();
  assert.throws(()=>meter.push(new Float32Array(480)), /disposed/);
});
