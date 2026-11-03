import test from 'node:test';
import assert from 'node:assert/strict';
import {createCapture} from '../../apps/client/web/audio/capture-bridge.mjs';

test('capture exposes no speaker enrollment or identity operations', () => {
  const capture = createCapture({onEvent() {}, platform: {}});
  assert.deepEqual(Object.keys(capture).sort(), ['start', 'stop']);
});
