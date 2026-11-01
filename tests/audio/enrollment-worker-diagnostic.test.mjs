import test from 'node:test';
import assert from 'node:assert/strict';
import {createSpeakerFlow} from '../../apps/client/web/audio/speaker-flow.mjs';

test('completing enrollment keeps the initialized worker for verification', async () => {
  let cancels = 0;
  const flow = createSpeakerFlow({embed: async () => new Float32Array([1, 0]), cancel: () => cancels++, now: () => 4, onStatus() {}});
  flow.begin();
  const afterBegin = cancels;
  for (let i = 0; i < 3; i++) await flow.feed(new Float32Array(16000).fill(.01), {startTime: i, endTime: i + 1, speechFrames: 90, clipped: false});
  assert.equal(flow.registered, true);
  assert.equal(cancels, afterBegin);
});
