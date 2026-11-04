// Mock worker protocol/lifecycle tests; not browser or microphone verification.
import test from 'node:test';
import assert from 'node:assert/strict';
import { AsrClient } from '../../apps/client/web/prosody/asr-client.js';
const tick = () => new Promise(resolve => setImmediate(resolve));
function fixture() {
  const original = { Worker:globalThis.Worker, isSecureContext:globalThis.isSecureContext,
    setTimeout:globalThis.setTimeout, clearTimeout:globalThis.clearTimeout };
  const workers=[],timers=new Map(),errors=[],results=[],progress=[];let timerId=0;
  globalThis.setTimeout=(fn,ms)=>{const id=++timerId;timers.set(id,{fn,ms});return id;};
  globalThis.clearTimeout=id=>timers.delete(id);
  class Worker {
    constructor(url,options){this.url=url;this.options=options;this.messages=[];this.transfers=[];this.terminations=0;workers.push(this);}
    postMessage(message,transfer){this.messages.push(message);this.transfers.push(transfer);}
    terminate(){this.terminations++;}
    send(message){this.onmessage?.({data:message});}
  }
  globalThis.Worker=Worker;globalThis.isSecureContext=true;
  const client=new AsrClient({onResult:r=>results.push(r),onProgress:p=>progress.push(p),onError:e=>errors.push(e)});
  return {client,workers,timers,errors,results,progress,
    async prepared(){const p=client.prepare();workers.at(-1).send({type:'ready'});await p;},
    restore(){client.stop();for(const [key,value] of Object.entries(original)) {
      if(value===undefined)delete globalThis[key];else globalThis[key]=value;
    }},
  };
}
const audio=(sequence=1)=>({samples:new Float32Array(1600),sampleRate:16000,sequence});
const result=(sequence=1)=>({type:'result',sequence,text:'한국어 인식 결과',endpoint:false});

test('lazy classic worker preparation is shared, bounded and reports progress',async()=>{
  const f=fixture();try{
    assert.equal(f.workers.length,0);assert.equal(f.client.prepared,false);
    const p=f.client.prepare();assert.equal(f.client.prepare(),p);
    const w=f.workers[0];assert.equal(w.options.type,'classic');assert.match(w.url.pathname,/\/asr-worker\.js$/);
    assert.deepEqual(w.messages,[{type:'init'}]);assert.equal([...f.timers.values()][0].ms,360000);
    w.send({type:'progress',loaded:4,total:10});assert.deepEqual(f.progress,[{loaded:4,total:10}]);
    w.send({type:'ready'});await p;assert.equal(f.client.prepared,true);assert.equal(f.timers.size,0);
    await f.client.prepare();assert.equal(f.workers.length,1);
  }finally{f.restore();}
});
test('PCM transfer resolves only for matching result and callback completion',async()=>{
  const f=fixture();try{
    await f.prepared();let release;f.client.onResult=()=>new Promise(resolve=>{release=resolve;});
    const chunk=audio(),p=f.client.consume(chunk),w=f.workers[0];
    assert.deepEqual(w.transfers.at(-1),[chunk.samples.buffer]);assert.equal([...f.timers.values()][0].ms,15000);
    assert.equal(w.messages.at(-1).type,'audio');w.send(result());
    await assert.rejects(f.client.consume(audio(2)),/outstanding/);
    release();assert.deepEqual(await p,{sequence:1,text:'한국어 인식 결과',endpoint:false});
    const next=f.client.consume(audio(2));w.send({...result(2),endpoint:true});release();await next;
    assert.equal(f.timers.size,0);
  }finally{f.restore();}
});
test('concurrent consume rejects without queueing or replacing the first chunk',async()=>{
  const f=fixture();try{await f.prepared();const p=f.client.consume(audio());
    await assert.rejects(f.client.consume(audio(2)),/outstanding/);assert.equal(f.workers[0].messages.length,2);
    f.workers[0].send(result());await p;assert.equal(f.results.length,1);
  }finally{f.restore();}
});
test('stop rejects initialization and decode, ignores late events, and permits fresh retry',async()=>{
  const f=fixture();try{
    const init=f.client.prepare(),old=f.workers[0],oldMessage=old.onmessage;
    const rejected=assert.rejects(init,{name:'AbortError'});f.client.stop();f.client.stop();await rejected;
    assert.equal(old.terminations,1);await f.prepared();oldMessage({data:{type:'ready'}});
    const decode=f.client.consume(audio()),rejectedDecode=assert.rejects(decode,{name:'AbortError'});
    f.client.stop();await rejectedDecode;assert.equal(f.errors.length,0);assert.equal(f.timers.size,0);
  }finally{f.restore();}
});
test('initialization and decode deadlines terminate worker and reject waiters',async()=>{
  for(const stage of ['init','decode']){const f=fixture();try{
    let p;if(stage==='init')p=f.client.prepare();else{await f.prepared();p=f.client.consume(audio());}
    const rejected=assert.rejects(p,/timed out/);[...f.timers.values()][0].fn();await rejected;
    assert.equal(f.workers[0].terminations,1);assert.equal(f.errors.length,1);assert.equal(f.client.prepared,false);
  }finally{f.restore();}}
});
test('wrong sequence, malformed result and unsolicited result fail explicitly',async()=>{
  for(const message of [result(2),{...result(),endpoint:'false'},{...result(),text:'x'.repeat(8001)}]){
    const f=fixture();try{await f.prepared();const p=f.client.consume(audio());const rejected=assert.rejects(p,/Invalid or out-of-order/);
      f.workers[0].send(message);await rejected;assert.equal(f.errors.length,1);assert.equal(f.results.length,0);
    }finally{f.restore();}
  }
  const f=fixture();try{await f.prepared();f.workers[0].send(result());assert.equal(f.client.prepared,false);}finally{f.restore();}
});
test('input validation rejects gaps, nonfinite PCM, changed rates and shared/subarray buffers',async()=>{
  const f=fixture();try{await f.prepared();
    for(const chunk of [audio(2),{...audio(),samples:new Float32Array([NaN])},{...audio(),sampleRate:7999},
      {...audio(),samples:new Float32Array(3200).subarray(0,1600)},{...audio(),samples:new Float32Array(new SharedArrayBuffer(6400))}]){
      await assert.rejects(f.client.consume(chunk),/Invalid or discontinuous/);
    }
    assert.equal(f.workers[0].messages.length,1);
    const p=f.client.consume(audio());f.workers[0].send(result());await p;
    await assert.rejects(f.client.consume({...audio(2),sampleRate:48000}),/Invalid or discontinuous/);
  }finally{f.restore();}
});
test('worker and result callback errors are reported once and settle promises',async()=>{
  for(const mode of ['worker','message','remote','callback']){const f=fixture();try{
    await f.prepared();if(mode==='callback')f.client.onResult=()=>Promise.reject(new Error('render failed'));
    const p=f.client.consume(audio()),rejected=assert.rejects(p);
    if(mode==='worker')f.workers[0].onerror({preventDefault(){}});
    if(mode==='message')f.workers[0].onmessageerror();
    if(mode==='remote')f.workers[0].send({type:'error',message:'local decode failed'});
    if(mode==='callback')f.workers[0].send(result());
    await rejected;assert.equal(f.errors.length,1);assert.equal(f.workers[0].terminations,1);
  }finally{f.restore();}}
});
test('progress callback rejection fails initialization; error callback cannot leak rejection',async()=>{
  const f=fixture();try{
    f.client.onProgress=()=>Promise.reject(new Error('progress failed'));
    f.client.onError=()=>Promise.reject(new Error('ignored error handler failure'));
    const p=f.client.prepare(),rejected=assert.rejects(p,/progress failed/);
    f.workers[0].send({type:'progress',loaded:1,total:2});await rejected;await tick();
    assert.equal(f.workers[0].terminations,1);
  }finally{f.restore();}
});
test('unsupported environment and consume before preparation do not create worker',async()=>{
  const f=fixture();try{
    await assert.rejects(f.client.consume(audio()),/not prepared/);globalThis.isSecureContext=false;
    await assert.rejects(f.client.prepare(),/secure context/);assert.equal(f.workers.length,0);
  }finally{f.restore();}
});
test('postMessage transfer failure rejects and terminates the active worker',async()=>{
  const f=fixture();try{
    await f.prepared();f.workers[0].postMessage=()=>{throw new Error('transfer failed');};
    await assert.rejects(f.client.consume(audio()),/transfer failed/);
    assert.equal(f.workers[0].terminations,1);assert.equal(f.errors.length,1);assert.equal(f.timers.size,0);
  }finally{f.restore();}
});
