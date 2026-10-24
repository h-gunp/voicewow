import test from 'node:test';
import assert from 'node:assert/strict';
import { LevelMeter } from '../../apps/client/web/audio/level-meter.mjs';

test('rms_of_half_amplitude_is_minus_6_dbfs', () => {
  const [f] = new LevelMeter(48000).push(new Float32Array(4800).fill(.5));
  assert.equal(f.rms, .5);
  assert.ok(Math.abs(f.dbfs + 6.020599913) < 1e-8);
  assert.equal(f.sampleCount, 4800);
});
test('zero_is_null', () => {
  const [f] = new LevelMeter(44100).push(new Float32Array(4410));
  assert.deepEqual(f, {rms:0, peak:0, dbfs:null, normalized:0, sampleCount:4410});
});
for (const rate of [44100,48000]) test(`window_crosses_blocks_${rate}`, () => {
  const meter = new LevelMeter(rate), frames=[];
  let remaining=rate/5;
  while(remaining) { const n=Math.min(128,remaining); frames.push(...meter.push(new Float32Array(n).fill(.25))); remaining-=n; }
  assert.equal(frames.length,2);
  for(const f of frames) { assert.equal(f.sampleCount,rate/10); assert.equal(f.rms,.25); }
});
test('normalization_clamps_and_partial_window_is_retained', () => {
  const m=new LevelMeter(1000);
  assert.equal(m.push(new Float32Array(50).fill(1)).length,0);
  assert.equal(m.push(new Float32Array(50).fill(1))[0].normalized,1);
  assert.equal(m.push(new Float32Array(100).fill(0.000001))[0].normalized,0);
});
test('nonfinite_input_fails', () => {
  for(const n of [NaN,Infinity,-Infinity]) assert.throws(()=>new LevelMeter(1000).push(new Float32Array([n])), /finite/i);
});
test('invalid_configuration_fails', () => {
  for(const rate of [0,-1,NaN,Infinity]) assert.throws(()=>new LevelMeter(rate));
  assert.throws(()=>new LevelMeter(48000,0));
});

test('peak_reports_the_largest_absolute_sample', () => {
  const [frame] = new LevelMeter(40).push([.25, -.75, .5, -.125]);
  assert.equal(frame.peak, .75);
});

test('peak_resets_after_each_completed_window', () => {
  const frames = new LevelMeter(20).push([-.75, .5, 0, 0]);
  assert.deepEqual(frames.map(frame => frame.peak), [.75, 0]);
});

test('peak_follows_window_boundaries_across_input_blocks', () => {
  const meter = new LevelMeter(40);
  assert.deepEqual(meter.push([-.875, .125]), []);
  const [first] = meter.push([.25, 0, .5]);
  const [second] = meter.push([.125, .25, -.75]);
  assert.equal(first.peak, .875);
  assert.equal(second.peak, .75);
});

test('peak_above_full_scale_is_preserved_for_clipping_detection', () => {
  const [frame] = new LevelMeter(20).push([.5, -1.25]);
  assert.equal(frame.peak, 1.25);
});
