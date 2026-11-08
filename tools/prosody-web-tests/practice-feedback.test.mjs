import test from 'node:test';
import assert from 'node:assert/strict';
import { describeSegmentPractice, describeGoal, buildPracticeSummary, choosePracticeRegions, EVIDENCE } from '../../apps/client/web/prosody/practice-feedback.js';
import { GUIDES } from '../../apps/client/web/prosody/guide-data.js';
import { analyzeAudio, trimAnalysis, compareAnalyses } from '../../apps/client/web/prosody/audio-analysis.js';
import { alignedTrace } from '../../apps/client/web/prosody/lab-utils.js';
import { cropReference } from '../../apps/client/web/prosody/practice-region.js';
import { readWav } from './wav-fixture.mjs';

function analysis(pitch = t => t * 6, level = t => t * 9) {
  return { duration: 1.2, frames: Array.from({ length: 61 }, (_, i) => {
    const time = i * .02;
    return { time, active: true, pitchHz: 180 * 2 ** (pitch(time) / 12),
      relativePitch: pitch(time), relativeDb: level(time) };
  }) };
}
const range = { start: 0, end: 1.2, userStart: 0, userEnd: 1.2 };
const directPath = { path: Array.from({ length: 61 }, (_, i) => [i, i]) };

test('explicit rise and fall tasks describe measured endpoints and give task-relative practice prompts', () => {
  const rising = describeGoal(analysis(), { ...range, target: 'fall' });
  assert.equal(rising.available, true);
  assert.equal(rising.direction, 'rise');
  assert.equal(rising.target, 'fall');
  assert.ok(rising.delta > 0);
  assert.match(rising.observation, /뒤쪽.*앞쪽보다.*높아요/);
  assert.match(rising.action, /끝의 음을 낮춰서 다시/);
  const falling = describeGoal(analysis(t => -t * 6), { ...range, target: 'rise' });
  assert.equal(falling.direction, 'fall');
  assert.match(falling.action, /끝의 음을 높여서 다시/);
  const same = describeGoal(analysis(), { ...range, target: 'rise' });
  assert.match(same.action, /다시 시도/);
  assert.doesNotMatch(same.action, /정확|맞았|성공|잘했|합격/);
});

test('rounded zero does not claim a flat contour or a normal range', () => {
  for (const curve of [() => 3, t => t * .01, t => Math.sin(t * Math.PI / 1.2) * 6]) {
    const result = describeGoal(analysis(curve), { ...range, target: 'fall' });
    assert.equal(result.available, true);
    assert.equal(result.direction, 'rounded-zero');
    assert.match(result.observation, /반올림하면 0.0반음/);
    assert.match(result.note, /앞·뒤 대표 구간을 비교한 값/);
    assert.doesNotMatch(result.observation, /평평|일정|변화가 없|유지/);
  }
});

test('static relative offsets and absolute errors never become movement directions', () => {
  const reference = analysis(), user = analysis(t => t * 6 + 8);
  const result = describeSegmentPractice(reference, user, { ...directPath, pitchError: 100 }, { ...range, pitchError: 100 });
  assert.equal(result.available, true);
  assert.equal(result.referenceDirection, 'rise');
  assert.equal(result.userDirection, 'rise');
  assert.ok(Math.abs(result.referenceDelta - result.userDelta) < 1e-10);
  assert.ok(Math.abs(result.relativeOffset - 8) < 1e-10);
  assert.doesNotMatch(result.action, /낮춰|줄여/);
  const opposite = describeSegmentPractice(reference, analysis(t => -t * 6 + 8), directPath, range);
  assert.equal(opposite.userDirection, 'fall');
  assert.match(opposite.action, /파란 선.*높여서/);
});

test('DTW repeated matches do not increase evidence or distort chronological endpoint medians', () => {
  const reference = analysis(), user = analysis(t => -t * 6);
  const normal = describeSegmentPractice(reference, user, directPath, range);
  const repeated = describeSegmentPractice(reference, user,
    { path: [...directPath.path, ...Array.from({ length: 300 }, () => [1, 1])] }, range);
  assert.equal(repeated.userDelta, normal.userDelta);
  assert.equal(repeated.referenceDelta, normal.referenceDelta);
  const sparse = describeSegmentPractice(reference, user,
    { path: Array.from({ length: 200 }, (_, i) => [i % 4, i % 4]) }, range);
  assert.equal(sparse.available, false);
  assert.equal(sparse.delta, null);
});

test('identical real guide contours use the same endpoint support on both sides despite unvoiced margins', () => {
  let measuredRegions = 0;
  for (const guide of GUIDES) {
    const a = guide.analysis, comparison = compareAnalyses(a, a);
    const summary = buildPracticeSummary(a, a, comparison);
    assert.ok(summary.segmentationNote.length > 0);
    for (const segment of summary.segments) {
      measuredRegions++;
      for (const tab of ['pitch', 'volume']) {
        const result = describeSegmentPractice(a, a, comparison, segment, tab);
        assert.equal(result.available, true, `${guide.id} ${segment.label} ${tab}`);
        assert.equal(result.referenceDelta, result.userDelta, `${guide.text} ${segment.label}`);
        assert.equal(result.referenceDirection, result.userDirection);
        assert.deepEqual(result.windows.reference, result.windows.user);
        assert.ok(result.windows.reference.first[1] < result.windows.reference.last[0]);
        assert.match(result.detail, /측정 구간/);
      }
    }
  }
  assert.equal(measuredRegions, 8, 'hello halves, sunglasses thirds and phrase thirds must all be supported');
});

test('volume comparison uses relative level direction and never claims calibrated dB SPL', () => {
  const result = describeSegmentPractice(analysis(), analysis(t => t * 6, t => -t * 9), directPath, range, 'volume');
  assert.equal(result.available, true);
  assert.equal(result.referenceDirection, 'rise');
  assert.equal(result.userDirection, 'fall');
  assert.match(result.observation, /작아요.*커요/);
  assert.match(result.detail, /dB.*커요.*dB.*작아요/);
  assert.match(result.action, /소리를.*키워서/);
  assert.match(result.note, /기준 크기에 대한 상대 dB/);
});

test('insufficient time support and truly sparse endpoint evidence abstain without quality judgement', () => {
  const short = describeGoal(analysis(), { start: 0, end: .1, target: 'rise' });
  assert.equal(short.available, false);
  const sparse = analysis();
  sparse.frames = sparse.frames.filter((_, i) => i % 8 === 0);
  assert.equal(describeGoal(sparse, { ...range, target: 'rise' }).available, false);
  const reference = analysis();
  const gapped = { ...reference, frames: reference.frames.map((frame, i) => i % 5 === 0 ? frame
    : { ...frame, active: false, pitchHz: null, relativePitch: null, relativeDb: null }) };
  assert.equal(describeSegmentPractice(reference, gapped, directPath, range).available, false);
});

test('an unvoiced gap elsewhere in an endpoint band does not erase its first independently measured block', () => {
  const gapped = analysis();
  for (const frame of gapped.frames) if (frame.time >= .08 && frame.time <= .24) {
    frame.active = false; frame.pitchHz = null; frame.relativePitch = null; frame.relativeDb = null;
  }
  const result = describeSegmentPractice(analysis(), gapped, directPath, range);
  assert.equal(result.available, true);
  assert.deepEqual(result.windows.user.first, [0, .06]);
  assert.ok(gapped.frames.filter(f => !f.active).every(f => f.relativePitch === null && f.relativeDb === null));
  // Selection must stay on that chronological block even if a later block
  // would have agreed better with the guide's rising contour.
  const shifted = { ...gapped, frames: gapped.frames.map(f => f.active && f.time <= .06
    ? { ...f, relativePitch: 20, pitchHz: 180 * 2 ** (20 / 12) } : f) };
  const opposite = describeSegmentPractice(analysis(), shifted, directPath, range);
  assert.equal(opposite.available, true);
  assert.equal(opposite.userDirection, 'fall');
  assert.deepEqual(opposite.windows.user.first, result.windows.user.first);
});

test('middle consonant or pause gaps do not invent a continuous path or erase usable endpoint evidence', () => {
  const gapped = analysis();
  for (const frame of gapped.frames) if (frame.time > .4 && frame.time < .8) {
    frame.active = false; frame.pitchHz = null; frame.relativePitch = null;
  }
  const result = describeGoal(gapped, { ...range, target: 'rise' });
  assert.equal(result.available, true);
  assert.match(result.observation, /뒤쪽의 대표 높이/);
  assert.match(result.note, /앞·뒤 대표 구간을 비교한 값/);
});

test('only explicit selected intervals and targets are evaluated, never inferred final syllables', () => {
  const a = analysis(t => t < .6 ? t * 6 : 7.2 - t * 6);
  const first = describeGoal(a, { start: 0, end: .54, target: 'rise' });
  const last = describeGoal(a, { start: .66, end: 1.2, target: 'rise' });
  assert.equal(first.direction, 'rise');
  assert.equal(last.direction, 'fall');
  for (const options of [undefined, {}, { ...range, target: 'question' }, { start: -1, end: 2, target: 'rise' },
    { start: .5, end: .5, target: 'fall' }, { start: NaN, end: 2, target: 'fall' }]) {
    assert.equal(describeGoal(a, options).available, false);
  }
  assert.equal(describeGoal(null, { ...range, target: 'fall' }).available, false);
});

test('output provides practice actions without scores, normative categories or unsupported word labels', () => {
  const outputs = [describeGoal(analysis(), { ...range, target: 'fall' }),
    describeGoal(analysis(() => 0), { ...range, target: 'rise' }),
    describeSegmentPractice(analysis(), analysis(t => -t * 6), directPath, range),
    describeSegmentPractice(null, null, null, null)];
  for (const output of outputs) {
    const mainCopy = [output.title, output.observation, output.action, output.cardLabel].join(' ');
    assert.doesNotMatch(mainCopy, /자연스럽|부자연|합격|불합격|점수|정상|비정상|잘했|성공|마지막 음절|단어가/);
    assert.equal(output.score, undefined);
    assert.equal(typeof output.action, 'string');
    assert.equal(typeof output.available, 'boolean');
  }
  assert.match(EVIDENCE.url, /^https:\/\/sunahjun\.humspace\.ucla\.edu\/ktobi\//);
  assert.match(EVIDENCE.note, /여러 억양/);
});


test('practice feedback recognises matching endpoint direction without a magnitude pass band', () => {
  for (const slope of [.3, 2, 18]) {
    const measured=describeSegmentPractice(analysis(),analysis(t=>t*slope),directPath,range);
    assert.equal(measured.tone,'encourage');
    assert.match(measured.title,/끝을 올려 읽었네요/);
    assert.match(measured.observation,/파란 예시도 같은 쪽/);
    assert.doesNotMatch(measured.observation,/반음|dB|정상|전체.*성공/);
    assert.match(measured.action,/다음 부분/);
    assert.match(measured.detail,/반음/);
  }
  const opposed=describeSegmentPractice(analysis(),analysis(t=>-t*6),directPath,range);
  assert.equal(opposed.tone,'practice');
  assert.match(opposed.action,/파란 선.*조금 높여서/);
  assert.doesNotMatch(opposed.action,/듣고|들어야|틀렸|불합격/);
  const missing=describeSegmentPractice(null,null,null,null);
  assert.equal(missing.available,false);
  assert.equal(missing.tone,'uncertain');
  assert.doesNotMatch(missing.action,/마이크 위치|잘못|실패/);
  assert.equal(missing.delta,null);
});

const boundaries = summary => summary.segments.map(({ label, start, end }) => ({ label, start, end }));
function realGuide(id) {
  const wav = readWav(new URL(`../../apps/client/web/prosody/guides/${id}.wav`, import.meta.url));
  return trimAnalysis(analyzeAudio(wav.samples, wav.sampleRate));
}

test('an unprepared guide has no fabricated preview ranges', () => {
  for (const reference of [null, undefined, { frames: [], duration: 0 }, { frames: [], duration: NaN }]) {
    const preview = choosePracticeRegions(reference);
    assert.deepEqual(preview.regions, []);
    assert.equal(typeof preview.segmentationNote, 'string');
  }
});

test('fresh bundled WAV analysis keeps all eight displayed guide regions measurable, without filling real gaps', () => {
  let regions = 0;
  for (const guide of GUIDES) {
    const a = realGuide(guide.id), comparison = compareAnalyses(a, a);
    const summary = buildPracticeSummary(a, a, comparison);
    assert.equal(summary.segments.length, guide.id === 'hello' ? 2 : 3);
    assert.deepEqual(boundaries(summary), choosePracticeRegions(a).regions);
    assert.equal(comparison.pitchError, 0);
    const trace = alignedTrace(a, a, comparison.path);
    for (let i = 0; i < a.frames.length; i++) {
      if (!a.frames[i].active) assert.equal(trace[i].relativePitch, null);
    }
    for (const segment of summary.segments) {
      regions++;
      for (const tab of ['pitch', 'volume']) assert.equal(describeSegmentPractice(a, a, comparison, segment, tab).available, true,
        `${guide.id} ${segment.label} ${tab}`);
    }
  }
  assert.equal(regions, 8);
  assert.ok(realGuide('phrase').frames.filter(f => !f.active).length > 5);
});

test('guide-only partitions stay fixed for opposite, noisy or missing user recordings', () => {
  const reference = realGuide('hello');
  const preview = choosePracticeRegions(reference);
  assert.deepEqual(preview.regions.map(s => s.label), ['앞부분', '뒷부분']);
  assert.match(preview.segmentationNote, /두 구간/);
  const opposite = { ...reference, frames: reference.frames.map(f => f.active
    ? { ...f, relativePitch: -f.relativePitch, relativeDb: -f.relativeDb } : f) };
  let seed = 17;
  const noise = Float32Array.from({ length: 16000 }, () => {
    seed = (1664525 * seed + 1013904223) >>> 0;
    return (seed / 4294967295 * 2 - 1) * .06;
  });
  const silence = trimAnalysis(analyzeAudio(new Float32Array(16000), 16000));
  const noisy = trimAnalysis(analyzeAudio(noise, 16000));
  for (const user of [opposite, silence, noisy]) {
    const comparison = compareAnalyses(reference, user);
    const summary = buildPracticeSummary(reference, user, comparison);
    assert.deepEqual(boundaries(summary), preview.regions);
    assert.equal(summary.segmentationNote, preview.segmentationNote);
    if (user === opposite) continue;
    assert.equal(user.voicedFrames, 0);
    for (const segment of summary.segments) {
      const feedback = describeSegmentPractice(reference, user, comparison, segment);
      assert.equal(feedback.available, false);
      assert.equal(feedback.userDelta, undefined);
      assert.equal(feedback.delta, null);
      assert.doesNotMatch(feedback.observation, /잘못|실패|정상|비정상/);
    }
  }
});

test('actual leading and internal pauses preserve gaps and do not alter the guide partition', () => {
  const wav = readWav(new URL('../../apps/client/web/prosody/guides/phrase.wav', import.meta.url));
  const split = Math.round(wav.sampleRate * .9), leading = Math.round(wav.sampleRate * .3), pause = Math.round(wav.sampleRate * .25);
  const samples = new Float32Array(wav.samples.length + leading + pause);
  samples.set(wav.samples.subarray(0, split), leading);
  samples.set(wav.samples.subarray(split), leading + split + pause);
  const reference = realGuide('phrase'), user = trimAnalysis(analyzeAudio(samples, wav.sampleRate));
  const comparison = compareAnalyses(reference, user), summary = buildPracticeSummary(reference, user, comparison);
  assert.ok(user.startTime > .2);
  assert.ok(user.frames.some(f => !f.active && f.relativePitch === null));
  assert.deepEqual(boundaries(summary), choosePracticeRegions(reference).regions);
  assert.ok(summary.segments.some(s => describeSegmentPractice(reference, user, comparison, s).available));
});

test('short excerpts fall back to whole without weakening support or splitting a selected interval', () => {
  const reference = cropReference({ analysis: realGuide('sunglasses') }, { start: .65, end: .85 }).analysis;
  const comparison = compareAnalyses(reference, reference);
  const summary = buildPracticeSummary(reference, reference, comparison);
  assert.equal(summary.segments.length, 1);
  assert.equal(summary.segments[0].label, '전체 흐름');
  assert.equal(describeSegmentPractice(reference, reference, comparison, summary.segments[0]).available, true);
  const whole = buildPracticeSummary(reference, reference, comparison, { whole: true });
  assert.equal(whole.segments.length, 1);
  assert.equal(whole.segments[0].label, '선택 구간 전체');
  assert.match(whole.segmentationNote, /선택한 구간/);
  const tooShort = { ...analysis(), duration: .1, frames: analysis().frames.filter(f => f.time <= .1) };
  const weak = buildPracticeSummary(tooShort, tooShort, { path: [], voicedPairs: 0 });
  assert.equal(weak.segments.length, 1);
  assert.match(weak.segmentationNote, /자료가 부족/);
  assert.equal(describeSegmentPractice(tooShort, tooShort, { path: [], voicedPairs: 0 }, weak.segments[0]).available, false);
});
