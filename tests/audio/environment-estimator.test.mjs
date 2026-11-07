import test from 'node:test';
import assert from 'node:assert/strict';
import {EnvironmentEstimator} from '../../apps/client/web/audio/environment-estimator.mjs';

function feed(e, from, count, power, speech='nonSpeech', clipped=false) {
  for (let seq=from;seq<from+count;seq++) e.add({seq,power,speech,clipped});
}

test('ambient evidence never starts sampling automatically', () => {
  const e=new EnvironmentEstimator();
  feed(e,0,1000,.0001);
  assert.equal(e.snapshot().state,'idle');
  assert.equal(e.snapshot().calibrationValid,false);
  assert.equal(e.snapshot().noiseDbfs,null);
  assert.equal(e.snapshot().offset,null);
  assert.equal(e.snapshot().progress,0);
});

for (const speech of ['speech','nonSpeech','uncertain']) test(`manual sampling includes raw ${speech} frames and finishes at 500`, () => {
  const e=new EnvironmentEstimator(); e.sample();
  feed(e,0,499,.00001,speech);
  assert.equal(e.snapshot().state,'collecting');
  assert.equal(e.snapshot().progress,.998);
  feed(e,499,1,.00001,speech);
  assert.equal(e.snapshot().state,'ready');
  assert.equal(e.snapshot().calibrationValid,true);
  assert.equal(e.snapshot().noiseDbfs,-50);
  assert.equal(e.snapshot().offset,1);
  assert.equal(e.snapshot().progress,1);
});

for (const [dbfs,offset] of [[-80,0],[-60,0],[-55,0.5],[-47,1.3],[-40,2],[-30,3],[-20,3]]) test(`experimental fixed offset at ${dbfs} dBFS is ${offset}`, () => {
  const e=new EnvironmentEstimator(); e.sample(); feed(e,0,500,10**(dbfs/10));
  assert.equal(e.snapshot().offset,offset);
});

test('median uses raw power and ignores a minority of transient bursts', () => {
  const e=new EnvironmentEstimator(); e.sample();
  feed(e,0,450,.00001); feed(e,450,50,.1,'speech');
  assert.equal(e.snapshot().noiseDbfs,-50);
  assert.equal(e.snapshot().offset,1);
});

test('successful guideline remains frozen during long speech, silence and changed ambience', () => {
  const e=new EnvironmentEstimator(); e.sample(); feed(e,0,500,.00001);
  feed(e,500,10000,.1,'speech'); feed(e,10500,10000,0); feed(e,20500,10000,.01,'uncertain');
  assert.equal(e.snapshot().state,'ready'); assert.equal(e.snapshot().calibrationValid,true);
  assert.equal(e.snapshot().noiseDbfs,-50); assert.equal(e.snapshot().offset,1);
  assert.equal(e.snapshot().voiceDbfs,null);
});

test('cancel and failed resampling preserve a previous successful result', () => {
  const e=new EnvironmentEstimator(); e.sample(); feed(e,0,500,.00001);
  e.sample(); feed(e,500,100,.0001);
  assert.equal(e.snapshot().calibrationValid,true); assert.equal(e.snapshot().offset,1);
  e.cancel(); assert.equal(e.snapshot().state,'ready'); assert.equal(e.snapshot().offset,1);
  e.sample(); feed(e,600,500,0);
  assert.equal(e.snapshot().state,'failed'); assert.equal(e.snapshot().reason,'insufficient_samples');
  assert.equal(e.snapshot().calibrationValid,true); assert.equal(e.snapshot().offset,1);
  e.sample(); feed(e,1100,500,.0001);
  assert.equal(e.snapshot().state,'ready'); assert.equal(e.snapshot().offset,2);
});

test('cancel without a previous result returns idle and late frames cannot finish it', () => {
  const e=new EnvironmentEstimator(); e.sample(); feed(e,0,499,.00001); e.cancel();
  feed(e,499,1000,.00001);
  assert.equal(e.snapshot().state,'idle'); assert.equal(e.snapshot().calibrationValid,false);
});

for (const [positive,clipped,want,reason] of [[400,0,'ready',null],[399,0,'failed','insufficient_samples'],[451,49,'ready',null],[450,50,'failed','clipping'],[0,0,'failed','insufficient_samples']]) test(`sample quality accepts ${positive} positive frames and ${clipped} clipped frames only when valid`, () => {
  const e=new EnvironmentEstimator(); e.sample();
  feed(e,0,positive,.00001); feed(e,positive,clipped,.1,'speech',true); feed(e,positive+clipped,500-positive-clipped,0);
  assert.equal(e.snapshot().state,want); assert.equal(e.snapshot().reason,reason);
  assert.equal(e.snapshot().calibrationValid,want==='ready');
});

for (const [spread,want] of [[12,'ready'],[12.1,'failed']]) test(`IQR ${spread} dB has state ${want}`, () => {
  const e=new EnvironmentEstimator(); e.sample(); feed(e,0,250,1e-6); feed(e,250,250,1e-6*10**(spread/10));
  assert.equal(e.snapshot().state,want);
  if(want==='failed') assert.equal(e.snapshot().reason,'unstable_environment');
});

test('duplicate and out-of-order frames cannot advance sampling', () => {
  const e=new EnvironmentEstimator(); e.sample(); feed(e,0,100,.00001);
  for(let i=0;i<1000;i++) feed(e,i%100,1,.0001);
  assert.equal(e.snapshot().progress,.2); feed(e,100,400,.00001);
  assert.equal(e.snapshot().offset,1);
});

test('sequence gaps invalidate sampling and previous calibration without restarting it', () => {
  const e=new EnvironmentEstimator(); e.sample(); feed(e,0,500,.00001); e.sample();
  feed(e,501,1000,.0001);
  assert.equal(e.snapshot().state,'failed'); assert.equal(e.snapshot().reason,'input_gap');
  assert.equal(e.snapshot().calibrationValid,false); assert.equal(e.snapshot().offset,null);
});

test('stale hold and new epoch clear calibration and require explicit sampling again', () => {
  const e=new EnvironmentEstimator(); e.sample(); feed(e,0,500,.00001); e.hold('analysis_stale');
  assert.equal(e.snapshot().calibrationValid,false); assert.equal(e.snapshot().reason,'analysis_stale');
  e.resetEpoch(); feed(e,0,500,.0001);
  assert.equal(e.snapshot().calibrationValid,false); assert.equal(e.snapshot().speech,'nonSpeech');
  e.sample(); feed(e,500,500,.0001); assert.equal(e.snapshot().offset,2);
});

for (const data of [{power:NaN},{power:-1},{speech:'unknown'},{clipped:undefined}]) test(`invalid analysis frame rejected: ${Object.keys(data)}`, () => {
  const e=new EnvironmentEstimator(); e.sample();
  assert.throws(()=>e.add({seq:0,power:.01,speech:'speech',clipped:false,...data}),RangeError);
});

test('finite large powers cannot overflow the even median into an infinite calibration', () => {
  const e=new EnvironmentEstimator(); e.sample(); feed(e,0,500,Number.MAX_VALUE);
  assert.equal(e.snapshot().state,'ready'); assert.ok(Number.isFinite(e.snapshot().noiseDbfs));
  assert.equal(e.snapshot().offset,3);
});
