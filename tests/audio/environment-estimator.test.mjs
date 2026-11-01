import test from 'node:test';
import assert from 'node:assert/strict';
import {EnvironmentEstimator} from '../../apps/client/web/audio/environment-estimator.mjs';

function feed(e, from, count, power, speech='nonSpeech') {
  for (let i=from;i<from+count;i++) e.add({seq:i, power, speech, clipped:false});
}

test('new epoch clears sequence, evidence clock and speech while preserving baseline and offset', () => {
  const e=new EnvironmentEstimator();
  feed(e,0,1000,.01); feed(e,1000,8000,.03);
  const initial=e.initial, offset=e.offset;
  assert.ok(offset>0);
  e.resetEpoch();
  assert.equal(e.seq,-1); assert.equal(e.lastEvidence,-Infinity);
  assert.equal(e.speech,undefined); assert.equal(e.initial,initial); assert.equal(e.offset,offset);
  e.add({seq:0,power:.01,speech:'speech',clipped:false});
  assert.equal(e.snapshot().speech,'speech');
  e.add({seq:1,power:.01,speech:'nonSpeech',clipped:false});
  assert.equal(e.snapshot().speech,'nonSpeech');
});

test('requires fresh non-speech evidence and holds on stale or low SNR', () => {
  const e = new EnvironmentEstimator();
  feed(e, 0, 400, .01);
  assert.equal(e.snapshot().state, 'ready');
  feed(e, 400, 20, .011, 'speech');
  assert.equal(e.snapshot().voiceDbfs, null);
  feed(e, 420, 550, .1, 'speech');
  assert.equal(e.snapshot().state, 'held');
  assert.equal(e.snapshot().voiceDbfs, null);
});

test('repeated or out-of-order evidence cannot move target', () => {
  const e = new EnvironmentEstimator();
  feed(e, 0, 400, .01);
  feed(e, 400, 700, .04);
  const offset = e.snapshot().offset;
  for (let i=0;i<1000;i++) e.add({seq:1099, power:.04, speech:'nonSpeech', clipped:false});
  assert.equal(e.snapshot().offset, offset);
});

test('sustained change needs new evidence and excessive change is unsupported', () => {
  const e = new EnvironmentEstimator();
  feed(e, 0, 400, .01);
  feed(e, 400, 100, .03);
  assert.equal(e.snapshot().offset, 0);
  feed(e, 500, 1800, .03);
  assert.ok(e.snapshot().offset > 0);
  feed(e, 2300, 1800, .1);
  assert.equal(e.snapshot().state, 'unsupported');
  assert.equal(e.snapshot().offset, null);
});

test('speech and uncertain frames do not create initial noise evidence', () => {
  const e = new EnvironmentEstimator();
  feed(e, 0, 500, .01, 'speech');
  feed(e, 500, 500, .01, 'uncertain');
  assert.equal(e.snapshot().state, 'collecting');
  assert.equal(e.snapshot().noiseDbfs, null);
});

test('sustained return to baseline removes every adaptation step', () => {
  const e = new EnvironmentEstimator();
  feed(e, 0, 1000, .01);
  feed(e, 1000, 5000, .03);
  assert.ok(e.snapshot().offset > 0);
  feed(e, 6000, 10000, .01);
  assert.equal(e.snapshot().offset, 0);
});

test('multi-step rise returns through multiple stages to baseline', () => {
  const e = new EnvironmentEstimator();
  feed(e, 0, 1000, .01);
  feed(e, 1000, 8000, .038);
  assert.ok(e.snapshot().offset >= 2);
  feed(e, 9000, 10000, .01);
  assert.equal(e.snapshot().offset, 0);
});

test('continued steps do not require another full entry threshold', () => {
  const e = new EnvironmentEstimator();
  feed(e, 0, 1000, .01);
  feed(e, 1000, 8000, .03);
  assert.ok(e.snapshot().offset >= 2);
});

