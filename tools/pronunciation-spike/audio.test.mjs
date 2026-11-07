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
  assert.deepEqual(await to16kHz(input, 16000), input);
  await assert.rejects(to16kHz(new Float32Array(48000 * 21), 48000));
  await assert.rejects(to16kHz(Float32Array.of(Infinity), 48000));
});

test('resampling uses the browser OfflineAudioContext, with mono 16kHz and preserved duration', async () => {
  const previous = globalThis.OfflineAudioContext;
  let observed;
  globalThis.OfflineAudioContext = class {
    constructor(channels, length, rate) { observed = { channels, length, rate }; }
    createBuffer(channels, length, rate) { observed.input = { channels, length, rate }; return { copyToChannel() {} }; }
    createBufferSource() { return { connect() {}, start() {} }; }
    async startRendering() { return { getChannelData: () => new Float32Array(observed.length).fill(.2) }; }
  };
  try {
    assert.equal((await to16kHz(new Float32Array(48000).fill(.1), 48000)).length, 16000);
    assert.deepEqual(observed, { channels: 1, length: 16000, rate: 16000, input: { channels: 1, length: 48000, rate: 48000 } });
  } finally { if (previous === undefined) delete globalThis.OfflineAudioContext; else globalThis.OfflineAudioContext = previous; }
});
