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
for (const name of ['hello', 'phrase', 'sunglasses']) {
  test(`bundled spoken guide ${name} remains detected at normal and quiet gains`, async (t) => {
    const wav = await readFile(new URL(`../../apps/client/web/prosody/guides/${name}.wav`, import.meta.url));
    let start = 12;
    while (wav.toString('ascii', start, start + 4) !== 'data') start += 8 + wav.readUInt32LE(start + 4) + (wav.readUInt32LE(start + 4) % 2);
    const length = wav.readUInt32LE(start + 4) / 2; start += 8;
    const source = Float32Array.from({length}, (_, i) => wav.readInt16LE(start + i * 2) / 32768);
    for (const gain of [1, .1]) {
      const vad = await createVoiceActivity(await readFile(new URL('../../apps/client/web/audio/vendor/libfvad/libfvad.wasm', import.meta.url)));
      let vadPositive = 0; const originalProcess = vad.process.bind(vad);
      vad.process = samples => { const result = originalProcess(samples); if (result) vadPositive++; return result; };
      const frames = [];
      const meter = await createNoiseMeter(await readFile(new URL('../../apps/client/web/audio/vendor/rnnoise/rnnoise.wasm', import.meta.url)), 48000, {vad, onAnalysis: f => frames.push(f)});
      try {
        // Bundled guides are mono PCM16 at 24 kHz; linearly resample to 48 kHz.
        const input = Float32Array.from({length: source.length * 2}, (_, i) => gain * (source[Math.floor(i/2)] + (i%2 ? (source[Math.min(source.length-1, Math.floor(i/2)+1)]-source[Math.floor(i/2)])*.5 : 0)));
        meter.push(input);
        const speech = frames.filter(f => f.speech === 'speech');
        t.diagnostic(`${name} gain=${gain}: retained ${speech.length}/${vadPositive} VAD-positive frames`);
        assert.ok(speech.length / vadPositive >= .7, `${name} gain=${gain}: retained ${speech.length}/${vadPositive}`);
        assert.ok(speech.length >= 20, `${name} gain=${gain}: only ${speech.length} speech frames`);
      } finally { meter.dispose(); }
    }
  });
}
