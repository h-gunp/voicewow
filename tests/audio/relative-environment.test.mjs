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

test('relative input resets baseline and offset after a gap or stale hold', () => {
  const e = new EnvironmentEstimator({relative:true});
  feed(e,0,1000); feed(e,1000,5000,.03);
  assert.ok(e.snapshot().offset>0);
  e.add(frame(7000,.03));
  feed(e,7001,400,.03);
  assert.equal(e.snapshot().offset,0);
  feed(e,7401,550,.03,'speech');
  feed(e,7951,400,.03);
  assert.equal(e.snapshot().offset,0);
  assert.equal(e.snapshot().voiceDbfs,null);
});

