import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { readWav } from './wav-fixture.mjs';

// Load the browser ES module without introducing a package.json requirement.
const source = await readFile(new URL('../../apps/client/web/prosody/audio-analysis.js', import.meta.url), 'utf8');
const { analyzeAudio, analyzeFrame, trimAnalysis, compareAnalyses, summarizeComparison, isNonSpeechWindow } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const rate = 16000;
function tone(frequency, gain = 0.3, seconds = 1) {
  const data = new Float32Array(rate * seconds);
  for (let i = 0; i < data.length; i++) data[i] = gain * Math.sin(2 * Math.PI * frequency * i / rate);
  return data;
}

test('pitch is measured and absolute pitch/gain do not define contour similarity', () => {
  const first = analyzeAudio(tone(220), rate);
  const second = analyzeAudio(tone(165, 0.1), rate);
  assert.ok(Math.abs(first.pitchMedian - 220) < 2);
  assert.ok(Math.abs(second.pitchMedian - 165) < 2);
  const result = compareAnalyses(first, second);
  assert.ok(result.pitchError < 0.2);
  assert.ok(result.intensityError < 0.2);
});

test('different pitch shapes are not erased by relative normalization and alignment', () => {
  const changing = new Float32Array(rate * 2);
  const steady = tone(190, 0.3, 2);
  for (let i = 0; i < changing.length; i++) {
    const frequency = i < rate ? 150 : 240;
    changing[i] = 0.3 * Math.sin(2 * Math.PI * frequency * i / rate);
  }
  const reference = analyzeAudio(changing, rate);
  assert.ok(compareAnalyses(reference, reference).pitchError < 0.01);
  assert.ok(compareAnalyses(reference, analyzeAudio(steady, rate)).pitchError > 1);
});

test('silence and noise do not create a dependable pitch or fabricated score', () => {
  const silent = analyzeAudio(new Float32Array(rate), rate);
  assert.equal(silent.pitchMedian, null);
  assert.equal(compareAnalyses(silent, analyzeAudio(tone(220), rate)).pitchError, null);
  assert.ok(compareAnalyses(silent, analyzeAudio(tone(220), rate)).warnings.length);
  let seed = 123;
  const noise = new Float32Array(rate);
  for (let i = 0; i < rate; i++) {
    seed = (1664525 * seed + 1013904223) >>> 0;
    noise[i] = (seed / 4294967295 * 2 - 1) * 0.1;
  }
  assert.ok(analyzeAudio(noise, rate).voicedFraction < 0.1);
});

test('long audio is rejected before allocating the comparison matrix', () => {
  assert.throws(() => analyzeAudio(new Float32Array(31 * rate), rate), /30초/);
});

function seededNoise(length, gain = .01) {
  let seed = 317;
  return Float32Array.from({ length }, () => {
    seed = (1664525 * seed + 1013904223) >>> 0;
    return (seed / 4294967295 * 2 - 1) * gain;
  });
}
function contour() {
  let phase = 0;
  return Float32Array.from({ length: rate * 2 }, (_, i) => {
    const t = i / rate;
    const hz = 180 + 45 * Math.sin(t * Math.PI);
    const gain = .15 + .06 * Math.cos(t * Math.PI);
    phase += 2 * Math.PI * hz / rate;
    return gain * (Math.sin(phase) + .25 * Math.sin(2 * phase));
  });
}

test('added waiting time and noisy internal pauses do not become comparison frames', () => {
  const original = contour();
  const reference = trimAnalysis(analyzeAudio(original, rate));
  const padded = seededNoise(rate * 4.6, .006);
  // Same voice with 0.6 s initial wait, 1 s middle pause and 1 s final wait.
  for (let i = 0; i < rate; i++) padded[Math.round(.6 * rate) + i] += original[i];
  for (let i = rate; i < original.length; i++) padded[Math.round(1.6 * rate) + i] += original[i];
  const user = trimAnalysis(analyzeAudio(padded, rate));
  const comparison = compareAnalyses(reference, user);
  const summary = summarizeComparison(reference, user, comparison);
  assert.ok(comparison.pitchError < .3, `pitch difference ${comparison.pitchError}`);
  assert.ok(comparison.intensityError < 1, `level difference ${comparison.intensityError}`);
  assert.ok(Math.abs(user.voicedDuration - reference.voicedDuration) < .15);
  assert.ok(Math.abs(summary.duration.userRecording - 4.6) < .001);
  assert.ok(summary.duration.userExcluded > 2.5);
  assert.ok(summary.duration.userSpan > 2.9);
  assert.equal(summary.duration.user, user.voicedDuration);
  assert.ok(user.startTime > .5 && user.startTime < .7);
  for (const [ri, ui] of comparison.path) {
    assert.ok(reference.frames[ri].active && user.frames[ui].active);
    const originalTime = user.startTime + user.frames[ui].time;
    assert.ok(originalTime < 1.65 || originalTime > 2.55, `pause matched at ${originalTime}`);
  }
  assert.ok(user.frames.some(f => !f.active && f.relativeDb === null && f.relativePitch === null));
});

test('background-only clips with a short click have no level or pitch evaluation', () => {
  const noise = seededNoise(rate * 3, .06);
  noise[rate] = .99;
  const user = trimAnalysis(analyzeAudio(noise, rate));
  const comparison = compareAnalyses(analyzeAudio(contour(), rate), user);
  assert.equal(user.voicedDuration, 0);
  assert.equal(user.frames.length, 0);
  assert.equal(comparison.pitchError, null);
  assert.equal(comparison.intensityError, null);
  assert.deepEqual(comparison.path, []);
});

test('quiet periodic speech remains measurable without a fixed loud-voice threshold', () => {
  const quiet = analyzeAudio(tone(110, .002), rate);
  assert.ok(Math.abs(quiet.pitchMedian - 110) < 1);
  assert.ok(quiet.voicedDuration > .8);
  const live = analyzeFrame(tone(110, .002, .1), rate);
  assert.ok(live.active);
  assert.ok(Math.abs(live.pitchHz - 110) < 1);
});

test('too few independent voice frames cannot become reliable by repeated DTW matches', () => {
  const reference = analyzeAudio(contour(), rate);
  const weak = { ...reference, frames: reference.frames.slice(0, 4) };
  assert.deepEqual(compareAnalyses(reference, weak).path, []);
  const repeatedPath = reference.frames.map((_, i) => [i, 0]);
  const summary = summarizeComparison(reference, weak, { path: repeatedPath, voicedPairs: repeatedPath.length });
  assert.equal(summary.pitchReliable, false);
  assert.ok(summary.segments.every(s => s.pitchDelta === null && s.levelDelta === null));
});

test('opposite local differences do not disappear behind a signed median', () => {
  const reference = analyzeAudio(tone(200, .2, 2), rate);
  const user = { ...reference, frames: reference.frames.map((f, i) => ({ ...f,
    relativePitch: i % 2 ? 4 : -4, relativeDb: i % 2 ? 6 : -6 })) };
  const path = reference.frames.map((_, i) => [i, i]);
  const summary = summarizeComparison(reference, user, { path, voicedPairs: path.length });
  assert.ok(summary.pitchReliable);
  for (const segment of summary.segments) {
    assert.ok(Math.abs(segment.pitchError - 4) < 1e-10);
    assert.ok(Math.abs(segment.levelError - 6) < 1e-10);
  }
});

test('an explicit guide partition is retained with its note without changing recorded-duration accounting', () => {
  const reference = analyzeAudio(tone(200, .2, 2), rate);
  const user = analyzeAudio(tone(180, .1, 2), rate);
  const comparison = compareAnalyses(reference, user);
  const ranges = [{ label: '짧은 앞 구간', start: 0, end: .5 }, { label: '남은 시간', start: .5, end: 2 }];
  const summary = summarizeComparison(reference, user, comparison, { ranges, segmentationNote: '예시의 시간 구간이에요.' });
  assert.deepEqual(summary.segments.map(({ label, start, end }) => ({ label, start, end })), ranges);
  assert.equal(summary.segmentationNote, '예시의 시간 구간이에요.');
  assert.equal(summary.duration.referenceRecording, 2);
  assert.equal(summary.duration.userRecording, 2);
  assert.ok(summary.segments.every(segment => segment.pitchError < .2));
  const whole = summarizeComparison(reference, user, comparison, { whole: true });
  assert.equal(whole.segments.length, 1);
  assert.equal(whole.segments[0].label, '선택 구간 전체');
});

test('real Korean guide remains comparable with room noise, a low hum and added pauses', () => {
  const { samples, sampleRate } = readWav(new URL('../../apps/client/web/prosody/guides/phrase.wav', import.meta.url));
  const hop = Math.round(sampleRate * .02);
  // Pause at a quiet boundary within the middle half, keeping analysis hop alignment.
  let split = hop, minimum = Infinity;
  for (let at = Math.ceil(samples.length * .25 / hop) * hop; at < samples.length * .75; at += hop) {
    let energy = 0;
    for (let i = at - hop; i < at + hop; i++) energy += samples[i] * samples[i];
    if (energy < minimum) { minimum = energy; split = at; }
  }
  const leading = Math.round(sampleRate * .6), middle = Math.round(sampleRate * .8);
  const padded = seededNoise(samples.length + Math.round(sampleRate * 2.4), .001);
  // 100 Hz periodic hum is deliberately inside the supported pitch range.
  for (let i = 0; i < padded.length; i++) padded[i] += .0015 * Math.sin(2 * Math.PI * 100 * i / sampleRate);
  for (let i = 0; i < samples.length; i++) padded[leading + i + (i >= split ? middle : 0)] += samples[i];
  const reference = trimAnalysis(analyzeAudio(samples, sampleRate));
  const user = trimAnalysis(analyzeAudio(padded, sampleRate));
  const comparison = compareAnalyses(reference, user);
  assert.ok(comparison.pitchError < .4, `real guide pitch difference ${comparison.pitchError}`);
  assert.ok(comparison.intensityError < 1.2, `real guide level difference ${comparison.intensityError}`);
  assert.ok(Math.abs(user.voicedDuration - reference.voicedDuration) < .2);
  assert.ok(Math.abs(user.recordingDuration - reference.recordingDuration - 2.4) < .001);
  const gapStart = (leading + split) / sampleRate, gapEnd = gapStart + .8;
  for (const [, ui] of comparison.path) {
    const t = user.startTime + user.frames[ui].time;
    assert.ok(t < gapStart + .05 || t > gapEnd - .05, `hum-only gap matched at ${t}`);
  }
});

test('a periodic tone at voice-like level remains ambiguous, not a guaranteed noise rejection', () => {
  // This documents the scope: periodicity + energy is not speaker separation.
  // Do not report all excluded time as silence or claim background speech removal.
  const hum = analyzeAudio(tone(100, .08), rate);
  assert.ok(hum.voicedDuration > .8);
  assert.ok(Math.abs(hum.pitchMedian - 100) < 1);
});

test('long low-hum waiting time does not dominate a short spoken contour', () => {
  const short = tone(220, .2, .6);
  const padded = tone(100, .001, 18);
  padded.set(short, rate * 8);
  const reference = analyzeAudio(short, rate), user = analyzeAudio(padded, rate);
  const comparison = compareAnalyses(reference, user);
  assert.ok(Math.abs(user.pitchMedian - 220) < 1);
  assert.ok(Math.abs(user.voicedDuration - reference.voicedDuration) < .1);
  assert.ok(comparison.pitchError < .2);
  assert.ok(comparison.intensityError < .5);
});

test('speech classification excludes periodic background without deleting PCM or time', () => {
  const samples = tone(220, .3, 2), original = samples.slice();
  const full = analyzeAudio(samples, rate);
  const gated = analyzeAudio(samples, rate, [{start:0,end:1,nonSpeech:true}]);
  assert.deepEqual(samples, original);
  assert.equal(gated.frames.length, full.frames.length);
  assert.equal(gated.duration, full.duration);
  assert.ok(gated.frames.filter(frame => frame.time < .975).every(frame => !frame.active && frame.pitchHz === null));
  assert.ok(gated.frames.filter(frame => frame.time > 1.1).every(frame => frame.active));
  assert.ok(Math.abs(gated.pitchMedian - 220) < 2);
});

test('uncertain speech keeps the acoustic pitch check and does not become forced silence', () => {
  const samples = tone(220);
  assert.deepEqual(analyzeAudio(samples, rate, [{start:0,end:1,nonSpeech:false}]), analyzeAudio(samples, rate));
  const background = analyzeAudio(samples, rate, [{start:0,end:1,nonSpeech:true}]);
  assert.equal(background.voicedFrames, 0);
  assert.equal(background.pitchMedian, null);
});

test('VAD preserves analysis windows touching speech, uncertainty or unclassified gaps', () => {
  const ranges=[{start:0,end:.1,nonSpeech:false},{start:.1,end:.2,nonSpeech:true},{start:.2,end:1,nonSpeech:false}];
  assert.equal(isNonSpeechWindow(ranges,.08,.13),false);
  assert.equal(isNonSpeechWindow(ranges,.16,.21),false);
  assert.equal(isNonSpeechWindow(ranges,.12,.17),true);
  assert.equal(isNonSpeechWindow([{start:.1,end:.2,nonSpeech:true}],.08,.13),false);
  assert.equal(isNonSpeechWindow([{start:0,end:.1,nonSpeech:true},{start:.1,end:.2,nonSpeech:true}],.08,.13),true);
  const measured=analyzeAudio(tone(180),rate,ranges);
  for(const time of [.105,.185])assert.ok(measured.frames.find(frame=>Math.abs(frame.time-time)<1e-8).active);
  assert.equal(measured.frames.find(frame=>Math.abs(frame.time-.145)<1e-8).active,false);
});
