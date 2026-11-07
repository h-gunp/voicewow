import test from 'node:test';
import assert from 'node:assert/strict';
import {EnvironmentEstimator} from '../../apps/client/web/audio/environment-estimator.mjs';
import * as bridge from '../../apps/client/web/audio/capture-bridge.mjs';

const frame = (seq,power=.01,speech='nonSpeech') => ({seq,power,speech,clipped:false});
const feed = (e,start,count,power=.01,speech='nonSpeech') => { for(let i=start;i<start+count;i++) e.add(frame(i,power,speech)); };

test('processing provenance distinguishes absent, false, active and malformed settings', () => {
  assert.equal(bridge.processingProvenance?.({autoGainControl:false,noiseSuppression:false,echoCancellation:false}), 'verified');
  assert.equal(bridge.processingProvenance?.({echoCancellation:false}), 'relative_input');
  for (const value of [true,'all','remote-only',null,0]) assert.equal(bridge.processingProvenance?.({echoCancellation:value}), 'unavailable');
});

test('relative input uses explicit fixed calibration and gaps discard it', () => {
  const e = new EnvironmentEstimator();
  e.sample(); feed(e,0,500,.00001);
  assert.equal(e.snapshot().offset,1);
  feed(e,500,550,.03,'speech');
  assert.equal(e.snapshot().offset,1);
  e.add(frame(2000,.03)); feed(e,2001,1000,.03);
  assert.equal(e.snapshot().calibrationValid,false);
  assert.equal(e.snapshot().offset,null);
  assert.equal(e.snapshot().voiceDbfs,null);
  e.sample(); feed(e,3001,500,.0001);
  assert.equal(e.snapshot().offset,2);
});
