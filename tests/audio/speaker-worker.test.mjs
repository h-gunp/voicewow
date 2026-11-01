import test from 'node:test';
import assert from 'node:assert/strict';
import {createSpeakerWorker} from '../../apps/client/web/audio/speaker-worker.mjs';
import {createSpeakerSession} from '../../apps/client/web/audio/speaker-session.mjs';

class FakeWorker {
  constructor() { this.listeners=new Map();this.sent=[];this.terminated=false; }
  addEventListener(type,fn){this.listeners.set(type,fn);}
  removeEventListener(type,fn){if(this.listeners.get(type)===fn)this.listeners.delete(type);}
  postMessage(message){this.sent.push(message);}
  terminate(){this.terminated=true;}
  emit(type,data){this.listeners.get(type)?.({data});}
}
test('model loading and inference use separate deadlines and failures allow retry',async()=>{
 const workers=[],timers=new Map(),delays=[];let id=0;
 const adapter=createSpeakerWorker(()=>{const w=new FakeWorker();workers.push(w);return w;},{loadingTimeoutMs:60000,timeoutMs:10000,setTimer:(fn,ms)=>{delays.push(ms);timers.set(++id,fn);return id;},clearTimer:id=>timers.delete(id)});
 const first=adapter.run(new Float32Array([1]));assert.deepEqual(delays,[60000]);
 workers[0].emit('message',{id:workers[0].sent[0].id,phase:'inference'});assert.deepEqual(delays,[60000,10000]);assert.equal(timers.size,1);
 workers[0].emit('message',{id:workers[0].sent[0].id,error:true});await assert.rejects(first,/failed/);assert.equal(workers[0].terminated,true);
 const retry=adapter.run(new Float32Array([2]));assert.equal(delays.at(-1),60000);workers[1].emit('message',{id:workers[1].sent[0].id,phase:'inference'});workers[1].emit('message',{id:workers[1].sent[0].id,result:'ok'});assert.equal(await retry,'ok');adapter.cancel();
});
test('cancel terminates worker, rejects pending work and ignores late replies', async()=>{
 const workers=[];const worker=createSpeakerWorker(()=>{const w=new FakeWorker();workers.push(w);return w;});
 const first=worker.run(new Float32Array([1]));const firstId=workers[0].sent[0].id;worker.cancel();
 await assert.rejects(first,{name:'AbortError'});assert.equal(workers[0].terminated,true);
 workers[0].emit('message',{id:firstId,result:'old'});
 const next=worker.run(new Float32Array([2]));const nextId=workers[1].sent[0].id;
 workers[1].emit('message',{id:nextId,result:'new'});assert.equal(await next,'new');worker.cancel();
});
test('session profile changes and epoch reset cancel running worker and discard queued work',async()=>{
 const workers=[],events=[];const worker=createSpeakerWorker(()=>{const w=new FakeWorker();workers.push(w);return w;});
 const session=createSpeakerSession({run:v=>worker.run(v),cancel:()=>worker.cancel(),onResult:v=>events.push(v)});
 session.register(new Float32Array([1]));session.submit('one');await Promise.resolve();session.submit('queued');session.resetEpoch();
 assert.equal(workers[0].terminated,true);await new Promise(setImmediate);assert.deepEqual(events,[]);
 session.submit('two');await Promise.resolve();session.register(new Float32Array([2]));assert.equal(workers[1].terminated,true);
 await new Promise(setImmediate);session.submit('three');await Promise.resolve();session.remove();assert.equal(workers[2].terminated,true);
 await new Promise(setImmediate);assert.deepEqual(events,[]);assert.equal(session.registered,false);
});
test('worker errors and synchronous post failures discard the worker and allow a fresh one',async()=>{
 const workers=[];const adapter=createSpeakerWorker(()=>{const w=new FakeWorker();workers.push(w);return w;});
 const first=adapter.run('x');workers[0].emit('message',{id:999,result:'wrong'});workers[0].emit('error');
 await assert.rejects(first,/failed/);assert.equal(workers[0].terminated,true);
 const second=adapter.run('y');workers[1].emit('message',{id:workers[1].sent[0].id,result:'ok'});assert.equal(await second,'ok');adapter.cancel();
 const failing=createSpeakerWorker(()=>Object.assign(new FakeWorker(),{postMessage(){throw Error('clone');}}));
 await assert.rejects(failing.run('x'),/failed/);
});
test('subarray PCM is copied to an exact backing buffer without mutating the source',async()=>{
 let worker;const adapter=createSpeakerWorker(()=>worker=new FakeWorker());
 const source=new Float32Array([11,22,33,44]),job=adapter.run(source.subarray(1,2));
 const sent=worker.sent[0].value;
 assert.deepEqual([...sent],[22]);assert.equal(sent.buffer.byteLength,4);
 assert.deepEqual([...source],[11,22,33,44]);
 worker.emit('message',{id:worker.sent[0].id,result:'ok'});await job;adapter.cancel();
 assert.deepEqual([...source],[11,22,33,44]);
});
test('timeout terminates worker, removes timer and listeners, and ignores late messages',async()=>{
 let worker,timer,cleared=0;const adapter=createSpeakerWorker(()=>worker=new FakeWorker(),{timeoutMs:10,setTimer:fn=>(timer=fn,1),clearTimer:()=>{cleared++;timer=null;}});
 const job=adapter.run(new Float32Array([1])),old=worker,id=old.sent[0].id;timer();
 await assert.rejects(job,/timeout/i);assert.equal(old.terminated,true);assert.equal(old.listeners.size,0);assert.equal(timer,null);assert.equal(cleared,1);
 old.emit('message',{id,result:'late'});
});
test('messageerror frees listeners and timer and next worker can run',async()=>{
 const workers=[];let active=0;const adapter=createSpeakerWorker(()=>{const w=new FakeWorker();workers.push(w);return w;},{timeoutMs:10,setTimer:()=>{active++;return 1;},clearTimer:()=>{active--;}});
 const first=adapter.run(new Float32Array([1]));workers[0].emit('messageerror');await assert.rejects(first,/failed/);
 assert.equal(active,0);assert.equal(workers[0].listeners.size,0);assert.equal(workers[0].terminated,true);
 const next=adapter.run(new Float32Array([2]));workers[1].emit('message',{id:workers[1].sent[0].id,result:'ok'});assert.equal(await next,'ok');assert.equal(active,0);assert.equal(workers[1].listeners.size,0);adapter.cancel();
});
test('session timeout releases queue so only latest snapshot is retried',async()=>{
 const workers=[],timers=new Map(),results=[],errors=[];let seq=0;
 const adapter=createSpeakerWorker(()=>{const w=new FakeWorker();workers.push(w);return w;},{timeoutMs:10,setTimer:fn=>{timers.set(++seq,fn);return seq;},clearTimer:id=>timers.delete(id)});
 const session=createSpeakerSession({run:v=>adapter.run(v),cancel:()=>adapter.cancel(),onResult:v=>results.push(v),onError:e=>errors.push(e.message)});
 session.register(new Float32Array([1]));session.submit(new Float32Array([10]));await Promise.resolve();
 session.submit(new Float32Array([20]));const last=new Float32Array([30]);session.submit(last);last[0]=99;
 timers.get(1)();await new Promise(setImmediate);
 assert.equal(workers[0].terminated,true);assert.deepEqual([...workers[1].sent[0].value],[30]);
 assert.equal(errors.length,1);workers[1].emit('message',{id:workers[1].sent[0].id,result:'ok'});await new Promise(setImmediate);
 assert.deepEqual(results,['ok']);assert.equal(timers.size,0);assert.equal(workers[1].listeners.size,0);session.remove();
});
test('cancel clears timeout and wipes owned copy without touching caller PCM',async()=>{
 let worker,active=0;const adapter=createSpeakerWorker(()=>worker=new FakeWorker(),{timeoutMs:10,setTimer:()=>{active++;return 1;},clearTimer:()=>active--});
 const source=new Float32Array([11,22,33,44]),job=adapter.run(source.subarray(1,2)),owned=worker.sent[0].value;
 adapter.cancel();await assert.rejects(job,{name:'AbortError'});
 assert.deepEqual([...owned],[0]);assert.deepEqual([...source],[11,22,33,44]);assert.equal(worker.listeners.size,0);assert.equal(active,0);
});
