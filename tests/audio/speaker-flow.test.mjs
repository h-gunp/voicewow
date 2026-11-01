import test from 'node:test';import assert from 'node:assert/strict';
import {createSpeakerFlow} from '../../apps/client/web/audio/speaker-flow.mjs';
const frame=()=>new Float32Array(16000).fill(.01);
test('voluntary registration rejects poor quality and emits timestamped delayed experimental status',async()=>{
 let now=4.2;const events=[];const flow=createSpeakerFlow({embed:async()=>new Float32Array([1,0]),cancel:()=>{},now:()=>now,onStatus:e=>events.push(e)});
 flow.begin();await flow.feed(frame(),{startTime:0,endTime:1,speechFrames:20,clipped:false});assert.equal(events.at(-1).state,'quality');
 for(let i=0;i<3;i++)await flow.feed(frame(),{startTime:i,endTime:i+1,speechFrames:90,clipped:false});assert.equal(events.at(-1).state,'registered');
 await flow.feed(frame(),{startTime:3,endTime:4,speechFrames:90,clipped:false});await new Promise(setImmediate);
 assert.equal(events.at(-1).state,'similar');assert.equal(events.at(-1).startTime,3);assert.equal(events.at(-1).endTime,4);assert.ok(Math.abs(events.at(-1).delayMs-200)<1e-8);
 flow.remove();assert.equal(events.at(-1).state,'unregistered');
});
test('gap and removal drop delayed replies',async()=>{
 let resolve;const events=[];let slow=false;const flow=createSpeakerFlow({embed:()=>slow?new Promise(r=>resolve=r):Promise.resolve(new Float32Array([1,0])),cancel:()=>{},now:()=>4,onStatus:e=>events.push(e)});
 flow.begin();for(let i=0;i<3;i++)await flow.feed(frame(),{startTime:i,endTime:i+1,speechFrames:90,clipped:false});
 slow=true;await flow.feed(frame(),{startTime:3,endTime:4,speechFrames:90,clipped:false});await Promise.resolve();flow.resetEpoch();resolve(new Float32Array([1,0]));await new Promise(setImmediate);
 assert.notEqual(events.at(-1).state,'similar');flow.remove();
});
test('registration rejects inconsistent samples rather than averaging two voices',async()=>{
 const events=[];let count=0;const flow=createSpeakerFlow({embed:async()=>++count===2?new Float32Array([0,1]):new Float32Array([1,0]),cancel:()=>{},now:()=>4,onStatus:e=>events.push(e)});
 flow.begin();await flow.feed(frame(),{startTime:0,endTime:1,speechFrames:90,clipped:false});await flow.feed(frame(),{startTime:1,endTime:2,speechFrames:90,clipped:false});
 assert.equal(events.at(-1).state,'quality');await flow.feed(frame(),{startTime:2,endTime:3,speechFrames:90,clipped:false});assert.equal(events.at(-1).state,'registering');
 await flow.feed(frame(),{startTime:3,endTime:4,speechFrames:90,clipped:false});assert.equal(events.at(-1).state,'registered');flow.remove();
});
