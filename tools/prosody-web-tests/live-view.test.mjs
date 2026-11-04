import test from 'node:test';
import assert from 'node:assert/strict';
import { createLiveView } from '../../apps/client/web/prosody/live-view.js';

const frame = (time, pitchHz = 200, rmsDb = -30, active = true) => ({ time, pitchHz, rmsDb, active });

test('live time axis stays still between expansion boundaries and never moves observations to guide positions', () => {
  const view = createLiveView({ duration: 2, frames: [] });
  const a = view.update([frame(0), frame(.7)], .7);
  const b = view.update([frame(0), frame(.7), frame(1.8)], 1.8);
  assert.equal(a.domainSeconds, 2.2);
  assert.equal(b.domainSeconds, a.domainSeconds);
  assert.deepEqual(b.trace.map(item => item.time), [0, .7, 1.8]);
  const c = view.update([frame(0), frame(2.21)], 2.21);
  assert.equal(c.domainSeconds, 4.4);
  assert.equal(view.update([frame(0), frame(2.3)], 2.3).domainSeconds, c.domainSeconds);
  assert.equal(view.update([], 0).domainSeconds, c.domainSeconds, 'a pause cannot shrink the time axis');
});

test('isolated measurements and missing sections remain distinct, including the current pause', () => {
  const view = createLiveView(.3);
  const points = [frame(0), frame(.04, null), frame(.08, 220), frame(.12, 230, -32, false)];
  const result = view.update(points, .12);
  assert.equal(result.domainSeconds, 1.5, 'short guides still have room for live dots');
  assert.equal(result.trace.length, points.length);
  assert.equal(result.voicedFrames, 2);
  assert.equal(result.hasCurrentVoice, false);
  assert.ok(Number.isFinite(result.trace[0].relativePitch));
  assert.equal(result.trace[1].relativePitch, null);
  assert.ok(Number.isFinite(result.trace[2].relativePitch));
  assert.equal(result.trace[3].relativePitch, null, 'inactive periodic measurements do not become current voice');
  assert.equal(result.trace[3].relativeDb, null);
  assert.equal(view.update([...points, frame(.16, 240)], .16).hasCurrentVoice, true);
});

test('relative contours ignore overall voice register and gain but preserve measured pitch changes', () => {
  const a = [frame(0, 180, -36), frame(.04, 220, -30), frame(.08, 260, -26)];
  const b = a.map(item => ({ ...item, pitchHz: item.pitchHz * 1.5, rmsDb: item.rmsDb + 12 }));
  const left = createLiveView(2).update(a, .08);
  const right = createLiveView(2).update(b, .08);
  for (let i = 0; i < a.length; i++) {
    assert.ok(Math.abs(left.trace[i].relativePitch - right.trace[i].relativePitch) < 1e-10);
    assert.equal(left.trace[i].relativeDb, right.trace[i].relativeDb);
  }
  assert.ok(left.trace[0].relativePitch < 0);
  assert.ok(left.trace[2].relativePitch > 0);
});

test('reference and new extremes stay visible, and plot scales never shrink after a smaller update', () => {
  const view = createLiveView({ duration: 10, frames: [{ relativePitch: 12, relativeDb: -18 }] });
  const initial = view.update([], 0);
  assert.equal(initial.domainSeconds, 11);
  assert.ok(initial.pitchBound > 12);
  assert.ok(initial.levelBound > 18);
  const extreme = view.update([frame(0, 65, -75), frame(.04, 500, -10), frame(.08, 500, -10)], .08);
  assert.ok(extreme.pitchBound > Math.abs(extreme.trace[0].relativePitch));
  assert.ok(extreme.levelBound > Math.abs(extreme.trace[0].relativeDb));
  const smaller = view.update([frame(0), frame(.04)], .04);
  assert.equal(smaller.pitchBound, extreme.pitchBound);
  assert.equal(smaller.levelBound, extreme.levelBound);
});

test('silence and invalid values produce no fabricated trace, voice status or NaN output', () => {
  const result = createLiveView({ duration: NaN }).update([
    frame(0, null, -140), frame(.04, NaN, Infinity), frame(.08, -1, -20), frame(NaN), frame(Infinity), frame(-1),
  ], NaN);
  assert.equal(result.trace.length, 3);
  assert.equal(result.voicedFrames, 0);
  assert.equal(result.hasCurrentVoice, false);
  assert.ok(result.trace.every(item => item.relativePitch === null && item.relativeDb === null));
  assert.equal(result.domainSeconds, 1.5);
  assert.equal(result.pitchBound, 5);
  assert.equal(result.levelBound, 10);
  assert.doesNotMatch(JSON.stringify(result), /NaN|Infinity/);
});
