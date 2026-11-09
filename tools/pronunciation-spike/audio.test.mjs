import test from 'node:test';
import assert from 'node:assert/strict';
import { encodeWav, decodeWav, to16kHz } from './audio.mjs';

test('local WAV replay preserves PCM length, rate and sign without exporting a recording', () => {
  const bytes = encodeWav(Float32Array.of(-1, -.5, 0, .5, 1), 48000);
  const view = new DataView(bytes);
  assert.equal(new TextDecoder().decode(new Uint8Array(bytes, 0, 4)), 'RIFF');
  assert.equal(view.getUint32(24, true), 48000);
  assert.equal(view.getUint32(40, true), 10);
  assert.equal(view.getInt16(44, true), -32768);
  assert.equal(view.getInt16(48, true), 0);
  assert.equal(view.getInt16(52, true), 32767);
  const decoded = decodeWav(bytes);
  assert.equal(decoded.sampleRate, 48000);
  assert.deepEqual(decoded.samples.slice(0, 3), Float32Array.of(-1, -.5, 0));
  assert.throws(() => encodeWav(Float32Array.of(NaN), 16000));
  assert.throws(() => decodeWav(bytes.slice(0, -1)));
  view.setUint16(20, 3, true);
  assert.throws(() => decodeWav(bytes), /16비트/);
});

test('16kHz input does not need a resampler and invalid/oversized input is rejected', async () => {
  const input = new Float32Array(3200).fill(.1);
  const copy = await to16kHz(input, 16000);
  assert.deepEqual(copy, input);
  assert.notEqual(copy, input);
  await assert.rejects(to16kHz(new Float32Array(48000 * 21), 48000));
  await assert.rejects(to16kHz(Float32Array.of(Infinity), 48000));
  await assert.rejects(to16kHz(Float32Array.of(NaN), 48000));
});

test('other sample rates retain browser OfflineAudioContext conversion and duration', async () => {
  const previous = globalThis.OfflineAudioContext;
  let observed;
  globalThis.OfflineAudioContext = class {
    constructor(channels, length, rate) { observed = { channels, length, rate }; }
    createBuffer(channels, length, rate) { observed.input = { channels, length, rate }; return { copyToChannel() {} }; }
    createBufferSource() { return { connect() {}, start() {} }; }
    async startRendering() { return { getChannelData: () => new Float32Array(observed.length).fill(.2) }; }
  };
  try {
    assert.equal((await to16kHz(new Float32Array(44100).fill(.1), 44100)).length, 16000);
    assert.deepEqual(observed, { channels: 1, length: 16000, rate: 16000, input: { channels: 1, length: 44100, rate: 44100 } });
  } finally { if (previous === undefined) delete globalThis.OfflineAudioContext; else globalThis.OfflineAudioContext = previous; }
});

test('resampling limits finite overshoot but still rejects a non-finite renderer result', async () => {
  const previous = globalThis.OfflineAudioContext;
  let output = Float32Array.of(1.04, -1.02, .25);
  globalThis.OfflineAudioContext = class {
    createBuffer() { return {copyToChannel(){}}; }
    createBufferSource() { return {connect(){},start(){}}; }
    async startRendering() { return {getChannelData:()=>output}; }
  };
  try {
    assert.deepEqual(await to16kHz(new Float32Array(9), 44100), Float32Array.of(1,-1,.25));
    output = Float32Array.of(NaN);
    await assert.rejects(to16kHz(new Float32Array(9), 44100));
  } finally { if(previous===undefined)delete globalThis.OfflineAudioContext;else globalThis.OfflineAudioContext=previous; }
});

test('48kHz conversion rejects aliased high frequencies while preserving the speech passband', async () => {
  const rms = values => Math.sqrt(values.reduce((sum, value) => sum + value * value, 0) / values.length);
  for (const frequency of [500, 2000, 4000, 6000, 9000, 12000]) {
    const input = Float32Array.from({length: 48000}, (_, i) => .1 * Math.sin(2 * Math.PI * frequency * i / 48000));
    const before = input.slice();
    const result = await to16kHz(input, 48000);
    assert.equal(result.length, 16000);
    assert.deepEqual(input, before);
    const gain = rms(result.subarray(800, 15200)) / rms(input.subarray(2400, 45600));
    if (frequency <= 6000) assert.ok(gain > .99 && gain < 1.01, `${frequency}Hz gain ${gain}`);
    else assert.ok(gain < .002, `${frequency}Hz must be attenuated before decimation, gain ${gain}`);
  }
});

test('48kHz centered filtering preserves partial tails without inserting filter delay', async () => {
  for (const length of [1, 2, 3, 479, 480, 481, 959, 960, 961]) {
    const input = new Float32Array(length); input[length - 1] = .5;
    const result = await to16kHz(input, 48000);
    assert.equal(result.length, Math.ceil(length / 3));
    assert.ok(result.at(-1) > .07, `final sample must survive at length ${length}`);
  }
  const input = new Float32Array(99); input[48] = .5;
  const result = await to16kHz(input, 48000);
  assert.equal(result.indexOf(Math.max(...result)), 16, 'impulse remains at its original time');
  assert.ok(Math.abs(result[15] - result[17]) < 1e-8, 'centered impulse response');
});

test('48kHz FIR overshoot is clamped without mutating full-scale input', async () => {
  const input = Float32Array.from({length: 4800}, (_, i) => i < 2400 ? -1 : 1);
  const before = input.slice();
  const result = await to16kHz(input, 48000);
  assert.ok(result.includes(-1) && result.includes(1), 'full-scale step exercises overshoot limiting');
  assert.ok(result.every(value => Number.isFinite(value) && Math.abs(value) <= 1));
  assert.deepEqual(input, before);
});
