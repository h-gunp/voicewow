import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createVoiceActivity} from '../../apps/client/web/audio/voice-activity.mjs';
import {createNoiseMeter} from '../../apps/client/web/audio/noise-reducer.mjs';

test('real VAD accepts 10ms silence and rejects invalid input and use after disposal', async () => {
  const bytes = await readFile(new URL('../../apps/client/web/audio/vendor/libfvad/libfvad.wasm', import.meta.url));
  const vad = await createVoiceActivity(bytes);
  assert.equal(vad.process(new Float32Array(480)), false);
  assert.throws(() => vad.process(new Float32Array(479)), /frame/i);
  const bad = new Float32Array(480); bad[1] = NaN;
  assert.throws(() => vad.process(bad), /finite/i);
  vad.reset();
  assert.equal(vad.process(new Float32Array(480)), false);
  vad.dispose();
  assert.throws(() => vad.process(new Float32Array(480)), /disposed/i);
  assert.throws(() => vad.reset(), /disposed/i);
});

test('a single synthetic impulse does not trigger speech after RNNoise, including after reset', async () => {
  const vadBytes = await readFile(new URL('../../apps/client/web/audio/vendor/libfvad/libfvad.wasm', import.meta.url));
  const rnnoiseBytes = await readFile(new URL('../../apps/client/web/audio/vendor/rnnoise/rnnoise.wasm', import.meta.url));
  const vad = await createVoiceActivity(vadBytes);
  let frames = [];
  const meter = await createNoiseMeter(rnnoiseBytes, 48000, {vad, onAnalysis: frame => frames.push(frame)});
  const input = new Float32Array(48000 * 4);
  input[48000] = .9;
  try {
    for (let run = 0; run < 2; run++) {
      if (run) { meter.reset(); frames = []; }
      meter.push(input);
      assert.equal(frames.length, 399);
      assert.equal(frames.filter(frame => frame.speech === 'speech').length, 0);
    }
  } finally { meter.dispose(); }
});
