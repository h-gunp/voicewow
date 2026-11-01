import test from 'node:test';import assert from 'node:assert/strict';
import {createSpeakerEngine} from '../../apps/client/web/audio/speaker-engine.mjs';
const makeOrt=()=>({Tensor:class{constructor(type,data,dims){this.type=type;this.data=data;this.dims=dims;}},InferenceSession:{create:async()=>({inputNames:['feats'],outputNames:['embs'],async run(){return {embs:{data:new Float32Array([3,4])}};},async release(){}})}});
test('engine returns a normalized embedding and score without uploading PCM',async()=>{
 const engine=await createSpeakerEngine(makeOrt(),new Uint8Array([1]));
 const pcm=Float32Array.from({length:8000},(_,i)=>.1*Math.sin(i*.2));
 const embedding=await engine.embed(pcm);assert.deepEqual([...embedding].map(x=>Math.round(x*10)),[6,8]);
 assert.ok(Math.abs(engine.similarity(embedding,embedding)-1)<1e-6);await engine.dispose();
 await assert.rejects(engine.embed(pcm),/disposed/i);
});
test('engine rejects invalid embeddings and unusable model responses',async()=>{
 const ort=makeOrt();ort.InferenceSession.create=async()=>({inputNames:['feats'],outputNames:['embs'],run:async()=>({embs:{data:new Float32Array([0,0])}}),release:async()=>{}});
 const engine=await createSpeakerEngine(ort,new Uint8Array([1]));await assert.rejects(engine.embed(new Float32Array(8000)),/embedding/i);
 assert.throws(()=>engine.similarity(new Float32Array([NaN]),new Float32Array([1])),/embedding/i);await engine.dispose();
});
