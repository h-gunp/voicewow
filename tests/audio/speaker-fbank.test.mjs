import test from 'node:test';import assert from 'node:assert/strict';
import {speakerFbank} from '../../apps/client/web/audio/speaker-fbank.mjs';
test('tone fbank matches torchaudio 2.9.1 reference and removes per-bin means',()=>{
 const pcm=Float32Array.from({length:16000},(_,i)=>.2*Math.sin(2*Math.PI*440*i/16000));
 const f=speakerFbank(pcm);assert.equal(f.length,98);assert.equal(f[0].length,80);
 const expected=[-1.5370368957519531,-1.4821481704711914,-1.1957769393920898,-.9452810287475586];
 for(let j=0;j<4;j++)assert.ok(Math.abs(f[0][j]-expected[j])<.0002);
 for(let j=0;j<80;j++)assert.ok(Math.abs(f.reduce((a,row)=>a+row[j],0))<.0001);
});
test('fbank rejects non-finite or too short input',()=>{
 assert.throws(()=>speakerFbank(new Float32Array(399)),/samples/i);
 const pcm=new Float32Array(400);pcm[0]=NaN;assert.throws(()=>speakerFbank(pcm),/finite/i);
});
