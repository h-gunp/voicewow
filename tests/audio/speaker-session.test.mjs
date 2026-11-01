import test from 'node:test';
import assert from 'node:assert/strict';
import {createSpeakerSession} from '../../apps/client/web/audio/speaker-session.mjs';

test('deletion and epoch changes discard late replies and keep at most the latest queued job', async () => {
  const pending=[], accepted=[];
  const session=createSpeakerSession({run: value => new Promise(resolve => pending.push({value,resolve})), onResult: value => accepted.push(value)});
  session.register(new Float32Array([1,2]));
  session.submit(1); session.submit(2); session.submit(3);
  await Promise.resolve();
  assert.deepEqual(pending.map(x=>x.value),[1]);
  pending[0].resolve('first'); await new Promise(setImmediate);
  assert.deepEqual(pending.map(x=>x.value),[1,3]);
  session.resetEpoch(); pending[1].resolve('stale'); await new Promise(setImmediate);
  assert.deepEqual(accepted,['first']);
  session.submit(4); await Promise.resolve(); session.remove(); pending[2].resolve('deleted'); await new Promise(setImmediate);
  assert.deepEqual(accepted,['first']); assert.equal(session.registered,false);
  assert.equal(session.submit(5),false);
});

test('new page session starts unregistered and replacement invalidates in-flight work', async () => {
  let finish; const results=[];
  const s=createSpeakerSession({run:()=>new Promise(resolve=>finish=resolve),onResult:r=>results.push(r)});
  assert.equal(s.registered,false); s.register(new Float32Array([1])); s.submit(1); await Promise.resolve(); s.register(new Float32Array([2]));
  finish('old'); await new Promise(setImmediate); assert.deepEqual(results,[]);
  assert.equal(createSpeakerSession({run:async()=>{},onResult:()=>{}}).registered,false);
});

test('profile is copied and removal before the scheduled run prevents inference', async () => {
  const seen=[];
  const s=createSpeakerSession({run:async(_,p)=>seen.push([...p]),onResult:()=>{}});
  const embedding=new Float32Array([1,2]); s.register(embedding); embedding[0]=99;
  s.submit(1); await new Promise(setImmediate); assert.deepEqual(seen,[[1,2]]);
  s.submit(2); s.remove(); await new Promise(setImmediate); assert.deepEqual(seen,[[1,2]]);
});

test('removal in the same turn prevents a not-yet-started run', async () => {
  let calls=0;
  const s=createSpeakerSession({run:async()=>{calls++;},onResult:()=>{}});
  s.register(new Float32Array([1])); s.submit(1); s.remove();
  await new Promise(setImmediate); assert.equal(calls,0);
});

test('same-turn profile replacement and epoch reset invalidate scheduled jobs', async () => {
  const seen=[]; const s=createSpeakerSession({run:async(v,p)=>seen.push([v,...p]),onResult:()=>{}});
  s.register(new Float32Array([1])); s.submit('old'); s.register(new Float32Array([2])); s.submit('new');
  await new Promise(setImmediate); assert.deepEqual(seen,[['new',2]]);
  s.submit('old-epoch'); s.resetEpoch(); s.submit('new-epoch');
  await new Promise(setImmediate); assert.deepEqual(seen,[['new',2],['new-epoch',2]]);
});

test('failed run reports failure and continues with only latest queued work', async () => {
  let reject; const calls=[], errors=[], results=[];
  const s=createSpeakerSession({run:v=>{calls.push(v);return v===1?new Promise((_,r)=>reject=r):Promise.resolve(v);},onResult:v=>results.push(v),onError:e=>errors.push(e.message)});
  s.register(new Float32Array([1])); s.submit(1); await Promise.resolve(); s.submit(2); s.submit(3);
  reject(new Error('failure')); await new Promise(setImmediate);
  assert.deepEqual(calls,[1,3]); assert.deepEqual(errors,['failure']); assert.deepEqual(results,[3]);
});

test('session lifecycle does not call fetch', async () => {
  const original=globalThis.fetch; let calls=0;
  globalThis.fetch=()=>{calls++;throw Error('unexpected network');};
  try {
    const s=createSpeakerSession({run:async()=>1,onResult:()=>{}});
    assert.equal(s.registered,false); s.register(new Float32Array([1])); s.submit(1);
    await new Promise(setImmediate); s.remove(); assert.equal(calls,0);
  } finally { globalThis.fetch=original; }
});
test('queued PCM is copied at submission and replaced by the latest snapshot',async()=>{
 const pending=[],seen=[];const s=createSpeakerSession({run:v=>{seen.push([...v]);return new Promise(r=>pending.push(r));},onResult:()=>{}});
 s.register(new Float32Array([1]));s.submit(new Float32Array([7]));await Promise.resolve();
 const a=new Float32Array([11,22,33,44]);s.submit(a.subarray(1,2));a[1]=99;
 const b=new Float32Array([55,66,77]);s.submit(b.subarray(1,2));b[1]=88;
 pending[0]('first');await new Promise(setImmediate);
 assert.deepEqual(seen,[[7],[66]]);assert.deepEqual([...a],[11,99,33,44]);assert.deepEqual([...b],[55,88,77]);
 pending[1]('last');await new Promise(setImmediate);s.remove();
});
test('profile owned copy is cleared on deletion and caller profile remains unchanged',async()=>{
 let held;const original=new Float32Array([3,4]);
 const s=createSpeakerSession({run:async(_,profile)=>{held=profile;},onResult:()=>{}});
 s.register(original);s.submit(new Float32Array([1]));await new Promise(setImmediate);s.remove();
 assert.deepEqual([...held],[0,0]);assert.deepEqual([...original],[3,4]);
});
test('result keeps the time metadata of the submitted window',async()=>{
 let done;const seen=[];const s=createSpeakerSession({run:()=>new Promise(r=>done=r),onResult:(r,m)=>seen.push(m)});
 s.register(new Float32Array([1]));const meta={startTime:2,endTime:3};s.submit(new Float32Array([1]),meta);await Promise.resolve();meta.endTime=99;done('ok');await new Promise(setImmediate);
 assert.deepEqual(seen,[{startTime:2,endTime:3}]);s.remove();
});
