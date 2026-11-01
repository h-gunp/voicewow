import test from 'node:test';import assert from 'node:assert/strict';
import {createSpeakerWindow} from '../../apps/client/web/audio/speaker-window.mjs';
test('no PCM is emitted without explicit activation and each window aligns raw frames with VAD decisions',()=>{
 const out=[],c=createSpeakerWindow(x=>out.push(x));
 c.push(new Float32Array(480));c.analysis({seq:0,speech:'speech',clipped:false});assert.equal(out.length,0);
 c.enable();
 for(let seq=1;seq<=100;seq++){c.push(new Float32Array(480).fill(seq/1000));c.analysis({seq,speech:seq<=80?'speech':'nonSpeech',clipped:seq===40});}
 assert.equal(out.length,1);assert.equal(out[0].sampleStart,480);assert.equal(out[0].sampleEnd,48480);assert.equal(out[0].speechFrames,80);assert.equal(out[0].clipped,true);assert.equal(out[0].pcm.length,48000);
 assert.ok(Math.abs(out[0].pcm[0]-.001)<1e-7);assert.ok(Math.abs(out[0].pcm[47999]-.1)<1e-7);
});
test('gap and disable discard incomplete windows and forbid later PCM output',()=>{
 const out=[],c=createSpeakerWindow(x=>out.push(x));c.enable();for(let i=0;i<60;i++){c.push(new Float32Array(480));c.analysis({seq:i,speech:'speech',clipped:false});}
 c.reset();for(let i=0;i<60;i++){c.push(new Float32Array(480));c.analysis({seq:i,speech:'speech',clipped:false});}assert.equal(out.length,0);
 c.disable();for(let i=60;i<110;i++){c.push(new Float32Array(480));c.analysis({seq:i,speech:'speech',clipped:false});}assert.equal(out.length,0);
});
