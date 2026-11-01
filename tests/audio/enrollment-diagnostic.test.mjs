import test from 'node:test';
import assert from 'node:assert/strict';
import {createSpeakerFlow} from '../../apps/client/web/audio/speaker-flow.mjs';

test('repeated begin preserves accepted sample', async () => {
  const events = [];
  const flow = createSpeakerFlow({embed: async () => new Float32Array([1, 0]), cancel() {}, now: () => 0, onStatus: e => events.push(e)});
  flow.begin();
  await flow.feed(new Float32Array(16000).fill(.01), {startTime: 0, endTime: 1, speechFrames: 90, clipped: false});
  flow.begin();
  assert.equal(events.at(-1).samples, 1);
});
