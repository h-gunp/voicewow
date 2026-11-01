import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {webcrypto} from 'node:crypto';
import {loadSpeakerModel} from '../../apps/client/web/audio/speaker-model.mjs';

const partURLs=[1,2].map(i=>new URL(`../../apps/client/web/audio/vendor/speaker/voxceleb_resnet34.onnx.part${i}`,import.meta.url));
const original=await Promise.all(partURLs.map(path=>readFile(path)));
function fixture(kind='valid') {
 const returned=[],order=[],assembled=[];let created=0,digests=0;
 const load=()=>loadSpeakerModel({
  fetchPart:async index=>{
   order.push(index);if(kind==='http'&&index===1)return {ok:false};if(kind==='missing'&&index===1)throw Error('missing');
   let data=Uint8Array.from(original[kind==='reordered'?1-index:index]);
   if(kind==='truncated'&&index===1)data=data.slice(0,-1);
   if(kind==='corrupt'&&index===1)data[42]^=1;
   returned.push(data);return {ok:true,arrayBuffer:async()=>data.buffer};
  },
  digest:async bytes=>{digests++;if(kind==='whole-hash'&&digests===3)return new Uint8Array(32).buffer;return webcrypto.subtle.digest('SHA-256',bytes);},
  create:async bytes=>{created++;assert.equal(bytes.byteLength,26534127);assembled.push(new Uint8Array(bytes));if(kind==='create-fails')throw Error('initialization failed');return 'engine';},
 });
 return {load,returned,order,assembled,get created(){return created;}};
}
for(const kind of ['http','missing','truncated','reordered','corrupt','whole-hash']) test(`model loader rejects ${kind} before inference and clears fetched bytes`,async()=>{
 const f=fixture(kind);await assert.rejects(f.load());assert.equal(f.created,0);assert.ok(f.returned.every(bytes=>bytes.every(x=>x===0)));
});
test('model loader reconstructs unchanged parts in order and can retry',async()=>{
 const f=fixture();assert.equal(await f.load(),'engine');assert.equal(await f.load(),'engine');
 assert.deepEqual(f.order,[0,1,0,1]);assert.equal(f.created,2);assert.ok([...f.returned,...f.assembled].every(bytes=>bytes.every(x=>x===0)));
});
test('model initialization failure clears all local model buffers',async()=>{
 const f=fixture('create-fails');await assert.rejects(f.load(),/initialization/);assert.ok([...f.returned,...f.assembled].every(bytes=>bytes.every(x=>x===0)));
});
test('retry after a part HTTP failure loads both parts again',async()=>{
 let failed=false,created=0;const order=[];
 const load=()=>loadSpeakerModel({fetchPart:async index=>{order.push(index);if(index===1&&!failed){failed=true;return {ok:false};}const bytes=Uint8Array.from(original[index]);return {ok:true,arrayBuffer:async()=>bytes.buffer};},digest:bytes=>webcrypto.subtle.digest('SHA-256',bytes),create:async()=>{created++;return 'engine';}});
 await assert.rejects(load(),/HTTP/);assert.equal(await load(),'engine');assert.deepEqual(order,[0,1,0,1]);assert.equal(created,1);
});
test('cancellation while loading second part clears the first part',async()=>{
 const first=Uint8Array.from(original[0]), controller=new AbortController();let secondStarted;
 const started=new Promise(resolve=>secondStarted=resolve);
 const job=loadSpeakerModel({fetchPart:async index=>{if(index===0)return {ok:true,arrayBuffer:async()=>first.buffer};secondStarted();return new Promise((_,reject)=>controller.signal.addEventListener('abort',()=>reject(new DOMException('Aborted','AbortError')),{once:true}));},digest:bytes=>webcrypto.subtle.digest('SHA-256',bytes),create:()=>assert.fail('unexpected inference')});
 await started;controller.abort();await assert.rejects(job,{name:'AbortError'});assert.ok(first.every(x=>x===0));
});
