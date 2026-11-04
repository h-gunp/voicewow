import test from 'node:test';
import assert from 'node:assert/strict';
import { cropReference, playbackRange } from '../../apps/client/web/prosody/practice-region.js';
import { GUIDES } from '../../apps/client/web/prosody/guide-data.js';
import { compareAnalyses } from '../../apps/client/web/prosody/audio-analysis.js';

const near = (actual, expected, message) => assert.ok(Math.abs(actual - expected) < 1e-10, message);
function median(values) {
  const sorted = [...values].sort((a, b) => a - b), mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

test('a real guide excerpt has its own baseline, original audio offset and no invented gap points', () => {
  const guide = GUIDES.find(item => item.id === 'phrase'), original = structuredClone(guide);
  const start = .34, end = 1.04;
  const region = cropReference(guide, { start, end, label: '중간' });
  assert.equal(region.audioUrl, guide.audioUrl);
  assert.deepEqual(region.region, { start, end, label: '중간' });
  near(region.analysis.startTime, guide.analysis.startTime + start, 'playback offset must address original audio');
  near(region.analysis.duration, end - start);
  near(region.analysis.recordingDuration, end - start);
  const originalFrames = guide.analysis.frames.filter(frame => frame.time >= start && frame.time <= end);
  assert.equal(region.analysis.frames.length, originalFrames.length);
  const active = region.analysis.frames.filter(frame => frame.active);
  near(region.analysis.pitchMedian, median(active.map(frame => frame.pitchHz)));
  near(region.analysis.levelMedian, median(active.map(frame => frame.rmsDb)));
  near(median(active.map(frame => frame.relativeDb)), 0);
  assert.notEqual(region.analysis.pitchMedian, guide.analysis.pitchMedian, 'segment must not inherit the full phrase baseline');
  for (let i = 0; i < originalFrames.length; i++) {
    const frame = region.analysis.frames[i], originalFrame = originalFrames[i];
    near(frame.time, originalFrame.time - start);
    assert.equal(frame.active, originalFrame.active);
    if (!frame.active) {
      assert.equal(frame.pitchHz, null); assert.equal(frame.relativePitch, null); assert.equal(frame.relativeDb, null);
    } else {
      near(frame.relativePitch, 12 * Math.log2(frame.pitchHz / region.analysis.pitchMedian));
      near(frame.relativeDb, frame.rmsDb - region.analysis.levelMedian);
    }
  }
  assert.deepEqual(guide, original, 'creating a drill must preserve full-phrase reference state');
});

test('cropped real guide self-comparison stays zero and pitch/gain shifts do not create excerpt loss', () => {
  for (const guide of GUIDES) {
    const options = { start: 0, end: guide.analysis.duration * .8 };
    const cropped = cropReference(guide, options).analysis;
    const same = compareAnalyses(cropped, cropped);
    assert.ok(same.path.length >= 8);
    near(same.pitchError, 0); near(same.intensityError, 0);
    const shifted = structuredClone(guide);
    for (const frame of shifted.analysis.frames) {
      if (frame.active) { frame.pitchHz *= 1.3; frame.rmsDb += 7; }
    }
    const second = cropReference(shifted, options).analysis;
    const comparison = compareAnalyses(cropped, second);
    assert.ok(comparison.pitchError < 1e-10);
    assert.ok(comparison.intensityError < 1e-10);
    assert.equal(cropped.voicedFrames, cropped.frames.filter(frame => frame.active).length);
    near(cropped.voicedDuration, Math.min(cropped.duration, cropped.voicedFrames * .02));
    near(cropped.excludedDuration + cropped.voicedDuration, cropped.duration);
  }
});

test('nested excerpts retain the offset into the original audio', () => {
  const guide = GUIDES[0];
  const first = cropReference(guide, { start: .1, end: .9 });
  const second = cropReference(first, { start: .1, end: .6 });
  near(second.analysis.startTime, (guide.analysis.startTime || 0) + .2);
  near(second.analysis.duration, .5);
});

test('invalid, unsupported and sparse selections fail before replacing the reference', () => {
  const guide = GUIDES[0], end = guide.analysis.duration;
  for (const range of [undefined, {}, { start: -1, end }, { start: 0, end: end + .1 },
    { start: .4, end: .4 }, { start: .5, end: .2 }, { start: 0, end: NaN }]) {
    assert.throws(() => cropReference(guide, range), /시작보다 뒤에/);
  }
  assert.throws(() => cropReference(null, { start: 0, end: 1 }), /가이드 음성/);
  assert.throws(() => cropReference(guide, { start: 0, end: .05 }), /목소리가 충분하지/);
  const silent = structuredClone(guide);
  for (const frame of silent.analysis.frames) { frame.active = false; frame.pitchHz = null; }
  assert.throws(() => cropReference(silent, { start: 0, end }), /목소리가 충분하지/);
});

test('playback adds one original offset and includes context without changing the measured core', () => {
  const analysis = { duration: 4, recordingDuration: 6, startTime: 1 };
  const before = structuredClone(analysis);
  const range = playbackRange(analysis, { start: .5, end: 1.2 });
  near(range.coreStart, 1.5); near(range.coreEnd, 2.2);
  near(range.start, 1.25); near(range.end, 2.45);
  assert.equal(range.whole, false); assert.equal(range.context, .25);
  assert.deepEqual(analysis, before);
});

test('a genuinely short original WAV plays in full instead of cutting a short word into thirds', () => {
  const guide = GUIDES.find(item => item.id === 'sunglasses');
  const { duration, startTime, recordingDuration } = guide.analysis;
  const range = playbackRange(guide.analysis, { start: duration / 3, end: duration * 2 / 3 });
  assert.equal(range.whole, true);
  assert.equal(range.start, 0);
  assert.equal(range.end, recordingDuration);
  near(range.coreStart, startTime + duration / 3);
  near(range.coreEnd, startTime + duration * 2 / 3);
  // A short measured interval inside a long file must not play the whole file.
  assert.equal(playbackRange({ duration: 1, startTime: 4, recordingDuration: 7 },
    { start: .1, end: .7 }).whole, false);
});

test('playback context clamps to original file edges and remains configurable', () => {
  const first = playbackRange({ duration: 3, recordingDuration: 3.1, startTime: .05 },
    { start: 0, end: .4 });
  assert.equal(first.start, 0); near(first.end, .7);
  const last = playbackRange({ duration: 3, recordingDuration: 3.1, startTime: .05 },
    { start: 2.8, end: 3 });
  near(last.coreEnd, 3.05); assert.equal(last.end, 3.1);
  const unpadded = playbackRange(GUIDES[0].analysis, { start: .2, end: .6 },
    { context: 0, wholeBelow: 0 });
  assert.equal(unpadded.start, unpadded.coreStart);
  assert.equal(unpadded.end, unpadded.coreEnd);
  assert.equal(unpadded.whole, false);
});

test('nested excerpts retain original file duration and playback does not double their offsets', () => {
  const guide = GUIDES[0];
  const first = cropReference(guide, { start: .1, end: .9 });
  const second = cropReference(first, { start: .1, end: .6 });
  near(second.analysis.sourceDuration, guide.analysis.recordingDuration);
  const range = playbackRange(second.analysis, { start: .1, end: .3 },
    { context: .1, wholeBelow: 0 });
  near(range.coreStart, (guide.analysis.startTime || 0) + .3);
  near(range.coreEnd, (guide.analysis.startTime || 0) + .5);
  near(range.start, range.coreStart - .1);
  near(range.end, range.coreEnd + .1);
});

test('invalid playback times or padding fail instead of fabricating a playable interval', () => {
  const analysis = { duration: 2, recordingDuration: 3, startTime: .2 };
  for (const selection of [undefined, {}, { start: -1, end: 1 }, { start: 1, end: 1 },
    { start: .5, end: 3 }, { start: 0, end: NaN }]) {
    assert.throws(() => playbackRange(analysis, selection), /시작보다 뒤에/u);
  }
  for (const options of [{ context: -1 }, { context: Infinity }, { wholeBelow: NaN }, { wholeBelow: -1 }]) {
    assert.throws(() => playbackRange(analysis, { start: 0, end: 1 }, options), /재생 여유 시간/u);
  }
  assert.throws(() => playbackRange(null, { start: 0, end: 1 }), /원본 음성/u);
  assert.throws(() => playbackRange({ ...analysis, startTime: NaN }, { start: 0, end: 1 }), /원본 음성/u);
  assert.throws(() => playbackRange({ ...analysis, startTime: 4 }, { start: 0, end: 1 }), /원본 음성 범위/u);
});
