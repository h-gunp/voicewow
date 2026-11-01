import test from 'node:test';import assert from 'node:assert/strict';
import {createSpeakerResampler} from '../../apps/client/web/audio/speaker-resample.mjs';
test('48k to 16k stream matches torchaudio sinc reference and gap clears history',()=>{
 const pcm=Float32Array.from({length:48001},(_,i)=>i===24000?.8:0),r=createSpeakerResampler(),output=[];
 for(let i=0;i<pcm.length;i+=127)output.push(...r.push(pcm.subarray(i,i+127)));
 output.push(...r.finish());assert.equal(output.length,16001);
 const expected=[-.00201072683557868,.0024910930078476667,.2640000283718109,.0024910930078476667,-.00201072683557868];
 for(let i=0;i<5;i++)assert.ok(Math.abs(output[7998+i]-expected[i])<1e-6);
 r.push(new Float32Array([1,1,1]));r.reset();assert.ok([...r.push(new Float32Array(100)),...r.finish()].every(x=>x===0));
});
