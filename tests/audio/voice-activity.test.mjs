import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createVoiceActivity} from '../../apps/client/web/audio/voice-activity.mjs';

test('real VAD accepts 10ms silence and rejects invalid input and use after disposal', async () => {
  const bytes = await readFile(new URL('../../apps/client/web/audio/vendor/libfvad/libfvad.wasm', import.meta.url));
  const vad = await createVoiceActivity(bytes);
  assert.equal(vad.process(new Float32Array(480)), false);
  assert.throws(() => vad.process(new Float32Array(479)), /frame/i);
  const bad = new Float32Array(480); bad[1] = NaN;
  assert.throws(() => vad.process(bad), /finite/i);
  vad.dispose();
  assert.throws(() => vad.process(new Float32Array(480)), /disposed/i);
});
