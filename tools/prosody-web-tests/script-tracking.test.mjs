import test from 'node:test';
import assert from 'node:assert/strict';
import {createScriptTracking} from '../../apps/client/web/prosody/script-tracking-ui.js';
const tick=()=>new Promise(resolve=>setImmediate(resolve));
function fixture(){
  const original=globalThis.Worker,workers=[],elements=new Map();
  globalThis.Worker=class {
    constructor(){this.messages=[];workers.push(this);}
    postMessage(message,transfer=[]){this.messages.push(structuredClone(message,{transfer}));}
    terminate(){this.terminated=true;}
    emit(data){this.onmessage?.({data});}
  };
  const document={getElementById(id){if(!elements.has(id))elements.set(id,{textContent:''});return elements.get(id);}};
  const tracking=createScriptTracking({document,cancelTts(){}});
  return {tracking,workers,elements,
    async prepare(){const pending=tracking.prepare();workers.at(-1).emit({type:'ready'});await pending;tracking.attach('안녕하세요.',['안녕하세요.'],0);},
    close(){tracking.stop();if(original===undefined)delete globalThis.Worker;else globalThis.Worker=original;},
  };
}
const chunk=()=>({samples:Float32Array.from([.1,.2,.3]),sampleRate:48000});
const ack=(worker,sequence)=>worker.emit({type:'result',sequence,text:'안녕하세요',endpoint:false});

test('clean PCM is copied for ASR transfer and the final partial chunk drains serially',async()=>{
  const f=fixture();try{
    await f.prepare();const first=chunk(),tail=chunk(),saved=first.samples.slice();
    f.tracking.consume(first);f.tracking.consume(tail);await tick();
    const worker=f.workers[0];
    assert.deepEqual(first.samples,saved);
    assert.equal(worker.messages.filter(m=>m.type==='audio').length,1);
    assert.deepEqual(worker.messages[1].samples,saved);
    let drained=false;const done=f.tracking.drain().then(()=>{drained=true;});
    assert.equal(drained,false);ack(worker,1);await tick();
    assert.equal(worker.messages.at(-1).sequence,2);
    assert.equal(drained,false);ack(worker,2);await done;
    assert.equal(drained,true);assert.equal(tail.samples.length,3);
  }finally{f.close();}
});

test('slow ASR has a bounded queue and cannot hold up the recording consumer',async()=>{
  const f=fixture();try{
    await f.prepare();for(let i=0;i<5;i++)f.tracking.consume(chunk());
    await f.tracking.drain();assert.equal(f.workers[0].terminated,true);
    assert.match(f.elements.get('asr-status').textContent,/녹음 속도/);
  }finally{f.close();}
});

test('cancelling pending ASR chunks cannot stop or enqueue audio into a new session',async()=>{
  const f=fixture();try{
    await f.prepare();f.tracking.consume(chunk());f.tracking.consume(chunk());await tick();
    const old=f.workers[0],oldDrain=f.tracking.drain();f.tracking.stop();
    await f.prepare();await oldDrain;await tick();
    const fresh=f.workers[1];assert.equal(fresh.terminated,undefined);
    assert.equal(old.messages.filter(m=>m.type==='audio').length,1);
    f.tracking.consume(chunk());await tick();assert.equal(fresh.messages.at(-1).sequence,1);
    ack(fresh,1);await f.tracking.drain();
  }finally{f.close();}
});
