import test from 'node:test';
import assert from 'node:assert/strict';
import { analyzeFrame, analyzeAudio, trimAnalysis, compareAnalyses, summarizeComparison } from '../../apps/client/web/prosody/audio-analysis.js';
import { makeDemo, alignedTrace, wavBytes, segmentObservation } from '../../apps/client/web/prosody/lab-utils.js';
import { GUIDES } from '../../apps/client/web/prosody/guide-data.js';
import { readWav } from './wav-fixture.mjs';

test('live pitch detects a voiced 220Hz frame and rejects silence',()=>{
  const frame=Float32Array.from({length:4096},(_,i)=>.2*Math.sin(2*Math.PI*220*i/48000));
  assert.ok(Math.abs(analyzeFrame(frame,48000).pitchHz-220)<2);
  assert.equal(analyzeFrame(new Float32Array(4096),48000).pitchHz,null);
});

test('bundled Korean guides are derived from real WAV data',()=>{
  for(const guide of GUIDES){
    const audio=readWav(new URL(`../../apps/client/web/prosody/${guide.audioUrl}`,import.meta.url));
    const actual=trimAnalysis(analyzeAudio(audio.samples,audio.sampleRate));
    assert.ok(actual.voicedFrames>20);
    assert.ok(Math.abs(actual.pitchMedian-guide.analysis.pitchMedian)<.001);
    assert.ok(actual.duration>.5);
    assert.equal(actual.frames.length,guide.analysis.frames.length);
  }
});

test('self comparison has near-zero differences and valid temporal regions',()=>{
  for(const {analysis:a} of GUIDES){
    const comparison=compareAnalyses(a,a),summary=summarizeComparison(a,a,comparison);
    assert.equal(comparison.pitchError,0);
    assert.equal(comparison.intensityError,0);
    assert.ok(summary.pitchReliable);
    assert.deepEqual(summary.segments.map(s=>s.label),['앞부분','중간','끝부분']);
    for(const segment of summary.segments){assert.ok(segment.userStart<=segment.userEnd);assert.ok(segment.userEnd<=a.duration);assert.ok(segment.pitchDelta===null||segment.pitchDelta===0);}
  }
});

test('controlled demo creates measurable differences and keeps duration separate',()=>{
  for(const {analysis:a} of GUIDES){
    const audio=makeDemo(a),user=trimAnalysis(analyzeAudio(audio.samples,audio.sampleRate));
    const comparison=compareAnalyses(a,user),summary=summarizeComparison(a,user,comparison);
    assert.ok(comparison.path.length>0);
    assert.ok(comparison.pitchError>.2);
    assert.ok(summary.duration.user>summary.duration.reference);
    assert.ok(summary.segments.some(s=>s.pitchDelta!==null&&Math.abs(s.pitchDelta)>.5));
    assert.equal(alignedTrace(a,user,comparison.path).length,a.frames.length);
    const bytes=wavBytes(audio.samples,audio.sampleRate);
    assert.equal(new DataView(bytes).getUint32(40,true),audio.samples.length*2);
  }
});

test('low evidence never receives confident segment pitch feedback',()=>{
  const a=GUIDES[0].analysis;
  const summary=summarizeComparison(a,a,{path:[[0,0]],voicedPairs:1});
  assert.equal(summary.pitchReliable,false);
  assert.ok(summary.segments.every(s=>s.pitchDelta===null));
});

test('leading and trailing silence are removed without changing internal pause',()=>{
  const rate=16000,samples=new Float32Array(rate*2);
  for(let i=rate*.2;i<rate*1.7;i++)if(!(i>rate*.8&&i<rate*1.0))samples[i]=.15*Math.sin(2*Math.PI*210*i/rate);
  const trimmed=trimAnalysis(analyzeAudio(samples,rate));
  assert.ok(trimmed.startTime>.1);
  assert.ok(trimmed.duration>1.4&&trimmed.duration<1.6);
  assert.ok(trimmed.frames.some(f=>!f.active));
  assert.ok(trimmed.voicedDuration<trimmed.duration);
  assert.equal(trimmed.recordingDuration,2);
});

test('observations show measurements without grades or correction advice',()=>{
  for(const difference of [0,.3,1,3,12]){
    const measured=segmentObservation({pitchDelta:difference,pitchError:difference});
    assert.equal(measured.kind,'observed');
    assert.equal(measured.label,`${difference.toFixed(1)}반음 차이`);
    assert.equal(measured.priority,undefined);
    assert.doesNotMatch(JSON.stringify(measured),/가까워요|비슷해요|낮춰|높여|잘했|다시 따라|합격|점수/);
  }
  const mixed=segmentObservation({pitchDelta:0,pitchError:4});
  assert.equal(mixed.label,'4.0반음 차이','opposite deviations must remain visible, not cancel to zero');
  assert.doesNotMatch(mixed.observation,/높게|낮게|올라|내려/,'a difference is not a temporal direction');
  const level=segmentObservation({levelDelta:-5,levelError:5},'volume');
  assert.equal(level.label,'5.0dB 차이');
  assert.match(level.detail,/중간 크기를 기준으로 비교한 상대 dB/);
  assert.doesNotMatch(level.observation,/더 강조|힘을 빼/);
});

test('insufficient or invalid observations stay unmeasured, never become zero',()=>{
  for(const value of [null,undefined,NaN,Infinity,-1]){
    const result=segmentObservation({pitchError:value});
    assert.equal(result.kind,'uncertain');
    assert.equal(result.label,'확인 어려움');
    assert.doesNotMatch(result.observation,/0.0|낮춰|높여/);
  }
});
