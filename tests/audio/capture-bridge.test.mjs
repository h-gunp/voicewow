import test from 'node:test';
import assert from 'node:assert/strict';
import { createCapture } from '../../apps/client/web/audio/capture-bridge.mjs';

function deferred() { let resolve,reject; const promise=new Promise((a,b)=>{resolve=a;reject=b;}); return {promise,resolve,reject}; }
function harness({permission, moduleGate}={}) {
  const events=[], nodes=[], timers=new Map(), deviceListeners=new Set(); let time=0, hidden=false, visibility;
  const track=new EventTarget(); track.readyState='live'; track.muted=false; track.stops=0;
  track.stop=()=>{track.stops++; track.readyState='ended';};
  track.getSettings=()=>({sampleRate:48000,echoCancellation:false});
  const stream={getTracks:()=>[track],getAudioTracks:()=>[track]};
  const makeNode=()=>{const n={connections:[],disconnected:false,connect(x){this.connections.push(x);return x;},disconnect(){this.disconnected=true;}};nodes.push(n);return n;};
  const ctx={state:'running',sampleRate:48000,get currentTime(){return time/1000;},destination:{},closed:0,resume:async()=>{},close:async()=>{ctx.closed++;ctx.state='closed';},audioWorklet:{addModule:async()=>{if(moduleGate)await moduleGate.promise;}},createMediaStreamSource:()=>makeNode(),createGain:()=>Object.assign(makeNode(),{gain:{value:1}})};
  const makeWorkletNode=()=>Object.assign(makeNode(),{port:{onmessage:null,closed:false,messages:[],postMessage(message){this.messages.push(message);},close(){this.closed=true;}},onprocessorerror:null});
  const node=makeWorkletNode(), port=node.port;
  const platform={calls:0,getUserMedia:async()=>{platform.calls++;return permission?permission.promise:stream;},createContext:()=>ctx,createWorkletNode:()=>node,now:()=>time,setInterval:fn=>{timers.set(1,fn);return 1;},clearInterval:id=>timers.delete(id),isHidden:()=>hidden,subscribeVisibility:fn=>{visibility=fn;return()=>{visibility=null;};},subscribeDeviceChange:fn=>{deviceListeners.add(fn);return()=>deviceListeners.delete(fn);}};
  const capture=createCapture({onEvent:e=>events.push(e),platform});
  return {capture,platform,ctx,track,stream,node,port,nodes,timers,events,deviceListeners,makeWorkletNode,frame(overrides={},target=node){target.port.onmessage?.({data:{type:'level',rms:.5,peak:.5,dbfs:-6.0206,normalized:.925,sampleCount:4800,...overrides}});},async changeDevice(){for(const fn of [...deviceListeners])fn();await settle();},async hide(){hidden=true;visibility?.();await settle();},async tick(ms){time+=ms;for(const fn of timers.values())fn();await settle();}};
}
async function settle(){for(let i=0;i<8;i++)await Promise.resolve();}

test('speaker capability is reported without starting speaker capture', async()=>{
 const h=harness();h.platform.speakerAvailable=()=>false;await h.capture.start();
 assert.equal(h.events.findLast(e=>e.type==='settings').settings.speakerAvailable,false);
 assert.equal(h.port.messages.some(m=>m.type==='speaker_capture'&&m.enabled),false);await h.capture.stop();
});

test('partial first window before enrollment is discarded without a false failure',async()=>{
 const h=harness(),{node}=addNoiseReduction(h);node.vadStatus='ready';let calls=0;
 h.platform.createSpeakerEmbedding=()=>({embed:async()=>{calls++;return new Float32Array([1,0]);},cancel:()=>{}});
 await h.capture.start();h.frame({},node);await h.tick(15);await h.capture.beginSpeakerEnrollment();
 node.port.onmessage({data:{type:'analysis',seq:1,sampleStart:480,sampleEnd:960,sampleTime:.02,power:.01,clipped:false,speech:'nonSpeech',meterRms:.1}});
 h.frame({},node);await h.tick(1000);const pcm=new Float32Array(48000).fill(.01);
 node.port.onmessage({data:{type:'speaker_window',generation:1,pcm,sampleStart:480,sampleEnd:48480,startTime:.01,endTime:1.01,speechFrames:90,clipped:false}});
 await settle();assert.equal(calls,0);assert.ok(pcm.every(x=>x===0));
 assert.equal(h.events.findLast(e=>e.type==='speaker').speaker.state,'registering');await h.capture.stop();
});

test('voluntary speaker enrollment stays separate from meter, preserves window time and deletes profile', async()=>{
 const h=harness(),{node}=addNoiseReduction(h);node.vadStatus='ready';
 h.platform.createSpeakerEmbedding=()=>({embed:async()=>new Float32Array([1,0]),cancel:()=>{}});
 await h.capture.start();
 assert.equal(h.events.some(e=>e.type==='speaker'),false);
 await h.capture.beginSpeakerEnrollment();
 assert.ok(node.port.messages.some(x=>x.type==='speaker_capture'&&x.enabled));
 node.port.onmessage({data:{type:'analysis',seq:0,sampleStart:0,sampleEnd:480,sampleTime:.01,power:.01,clipped:false,speech:'nonSpeech',meterRms:.1}});
 for(let i=0;i<4;i++){
  h.frame({},node);await h.tick(1000);
  node.port.onmessage({data:{type:'speaker_window',generation:1,pcm:new Float32Array(48000).fill(.01),sampleStart:i*48000,sampleEnd:(i+1)*48000,startTime:i,endTime:i+1,speechFrames:90,clipped:false}});
  await new Promise(setImmediate);
 }
 assert.ok(h.events.some(e=>e.type==='speaker'&&e.speaker.state==='registered'));
 const result=h.events.findLast(e=>e.type==='speaker'&&e.speaker.state==='similar');assert.ok(result);assert.equal(result.speaker.startTime,3);assert.equal(result.speaker.endTime,4);
 assert.ok(h.events.some(e=>e.type==='level'));h.capture.deleteSpeaker();assert.equal(h.events.at(-1).speaker.state,'unregistered');
 await h.capture.stop();
});

test('speaker enrollment fails closed when local model is unavailable', async()=>{
 const h=harness();const {node}=addNoiseReduction(h);node.vadStatus='ready';await h.capture.start();
 await h.capture.beginSpeakerEnrollment();assert.equal(h.events.at(-1).speaker.state,'unavailable');
 assert.equal(node.port.messages.some(x=>x.type==='speaker_capture'&&x.enabled),false);await h.capture.stop();
});
test('late permission cleanup cannot reset a newer speaker enrollment',async()=>{
 const h=harness(),oldPermission=deferred(),oldTrack={stops:0,stop(){this.stops++;}};let requests=0,cancels=0;
 h.platform.getUserMedia=()=>++requests===1?oldPermission.promise:Promise.resolve(h.stream);
 h.platform.createSpeakerEmbedding=()=>({embed:async()=>new Float32Array([1,0]),cancel:()=>{cancels++;}});
 const oldStart=h.capture.start();await h.capture.stop();h.ctx.state='running';
 const {node}=addNoiseReduction(h);node.vadStatus='ready';await h.capture.start();await h.capture.beginSpeakerEnrollment();
 const before=cancels,events=h.events.length;assert.equal(h.events.at(-1).speaker.state,'registering');
 oldPermission.resolve({getTracks:()=>[oldTrack]});await oldStart;await settle();
 assert.equal(oldTrack.stops,1);assert.equal(cancels,before);assert.equal(h.events.length,events);
 assert.equal(h.events.findLast(e=>e.type==='speaker').speaker.state,'registering');await h.capture.stop();
});
test('late noise module cleanup cannot reset a newer speaker enrollment',async()=>{
 const h=harness(),gate=deferred(),oldNode=h.makeWorkletNode();let cancels=0;
 h.platform.createNoiseReductionNode=()=>gate.promise;
 h.platform.createSpeakerEmbedding=()=>({embed:async()=>new Float32Array([1,0]),cancel:()=>{cancels++;}});
 const oldStart=h.capture.start();await settle();await h.capture.stop();h.ctx.state='running';h.track.readyState='live';
 const next=h.makeWorkletNode();next.vadStatus='ready';h.platform.createNoiseReductionNode=async()=>next;await h.capture.start();await h.capture.beginSpeakerEnrollment();
 const before=cancels,events=h.events.length;gate.resolve(oldNode);await oldStart;await settle();
 assert.equal(oldNode.port.closed,true);assert.equal(cancels,before);assert.equal(h.events.length,events);
 assert.equal(h.events.findLast(e=>e.type==='speaker').speaker.state,'registering');await h.capture.stop();
});
test('failed speaker inference discards queued audio and stop blocks late events',async()=>{
 const h=harness(),{node}=addNoiseReduction(h);node.vadStatus='ready';let calls=0,cancels=0;const failed=deferred(),late=deferred();
 h.platform.createSpeakerEmbedding=()=>({embed:()=>{calls++;return calls<=3?Promise.resolve(new Float32Array([1,0])):calls===4?failed.promise:late.promise;},cancel:()=>{cancels++;}});
 await h.capture.start();await h.capture.beginSpeakerEnrollment();
 node.port.onmessage({data:{type:'analysis',seq:0,sampleStart:0,sampleEnd:480,sampleTime:.01,power:.01,clipped:false,speech:'nonSpeech',meterRms:.1}});
 for(let i=0;i<5;i++){h.frame({},node);await h.tick(1000);node.port.onmessage({data:{type:'speaker_window',generation:1,pcm:new Float32Array(48000).fill(.01),sampleStart:i*48000,sampleEnd:(i+1)*48000,startTime:i,endTime:i+1,speechFrames:90,clipped:false}});await new Promise(setImmediate);}
 assert.equal(calls,4);failed.reject(Error('failed'));await new Promise(setImmediate);
 assert.equal(h.events.findLast(e=>e.type==='speaker').speaker.state,'unavailable');assert.equal(calls,4);
 const beforeStop=cancels;await h.capture.stop();assert.ok(cancels>beforeStop);
 const count=h.events.length;late.resolve(new Float32Array([1,0]));await new Promise(setImmediate);
 assert.equal(calls,4);assert.equal(h.events.length,count);
 const next=h.makeWorkletNode();next.vadStatus='ready';h.platform.createNoiseReductionNode=async()=>next;h.track.readyState='live';h.ctx.state='running';await h.capture.start();
 assert.ok(next.port.messages.some(message=>message.type==='speaker_capture'&&message.enabled));assert.equal(calls,4);await h.capture.stop();
});
test('stale speaker inference discards queued audio without deleting registration',async()=>{
 const h=harness(),{node}=addNoiseReduction(h);node.vadStatus='ready';let calls=0;const slow=deferred();
 h.platform.createSpeakerEmbedding=()=>({embed:()=>++calls<=3?Promise.resolve(new Float32Array([1,0])):slow.promise,cancel:()=>{}});
 await h.capture.start();await h.capture.beginSpeakerEnrollment();
 node.port.onmessage({data:{type:'analysis',seq:0,sampleStart:0,sampleEnd:480,sampleTime:.01,power:.01,clipped:false,speech:'nonSpeech',meterRms:.1}});
 for(let i=0;i<5;i++){h.frame({},node);await h.tick(1000);node.port.onmessage({data:{type:'speaker_window',generation:1,pcm:new Float32Array(48000).fill(.01),sampleStart:i*48000,sampleEnd:(i+1)*48000,startTime:i,endTime:i+1,speechFrames:90,clipped:false}});await new Promise(setImmediate);}
 assert.equal(calls,4);h.frame({},node);await h.tick(100);slow.resolve(new Float32Array([1,0]));await new Promise(setImmediate);
 assert.equal(h.events.findLast(e=>e.type==='speaker').speaker.state,'unavailable');assert.equal(calls,4);
 await h.capture.stop();const next=h.makeWorkletNode();next.vadStatus='ready';h.platform.createNoiseReductionNode=async()=>next;h.track.readyState='live';h.ctx.state='running';await h.capture.start();
 assert.ok(next.port.messages.some(message=>message.type==='speaker_capture'&&message.enabled));await h.capture.stop();
});
test('speaker gap discards in-flight status and immediate meter keeps working',async()=>{
 const h=harness(),{node}=addNoiseReduction(h);node.vadStatus='ready';let count=0;const delayed=deferred();
 h.platform.createSpeakerEmbedding=()=>({embed:()=>++count<=3?Promise.resolve(new Float32Array([1,0])):delayed.promise,cancel:()=>{}});
 await h.capture.start();await h.capture.beginSpeakerEnrollment();
 node.port.onmessage({data:{type:'analysis',seq:0,sampleStart:0,sampleEnd:480,sampleTime:.01,power:.01,clipped:false,speech:'nonSpeech',meterRms:.1}});
 for(let i=0;i<4;i++){h.frame({},node);await h.tick(1000);node.port.onmessage({data:{type:'speaker_window',generation:1,pcm:new Float32Array(48000).fill(.01),sampleStart:i*48000,sampleEnd:(i+1)*48000,startTime:i,endTime:i+1,speechFrames:90,clipped:false}});await settle();}
 assert.ok(h.events.some(e=>e.type==='speaker'&&e.speaker.state==='registered'));
 node.port.onmessage({data:{type:'analysis_reset'}});delayed.resolve(new Float32Array([1,0]));await settle();
 assert.equal(h.events.some(e=>e.type==='speaker'&&e.speaker.state==='similar'),false);
 h.frame({},node);assert.equal(h.events.at(-1).type,'level');h.capture.deleteSpeaker();await h.capture.stop();
});
test('speaker result expires even if no new speaker window arrives',async()=>{
 const h=harness(),{node}=addNoiseReduction(h);node.vadStatus='ready';h.platform.createSpeakerEmbedding=()=>({embed:async()=>new Float32Array([1,0]),cancel:()=>{}});
 await h.capture.start();await h.capture.beginSpeakerEnrollment();node.port.onmessage({data:{type:'analysis',seq:0,sampleStart:0,sampleEnd:480,sampleTime:.01,power:.01,clipped:false,speech:'nonSpeech',meterRms:.1}});
 for(let i=0;i<4;i++){h.frame({},node);await h.tick(1000);node.port.onmessage({data:{type:'speaker_window',generation:1,pcm:new Float32Array(48000).fill(.01),sampleStart:i*48000,sampleEnd:(i+1)*48000,startTime:i,endTime:i+1,speechFrames:90,clipped:false}});await new Promise(setImmediate);}
 assert.equal(h.events.findLast(e=>e.type==='speaker').speaker.state,'similar');h.frame({},node);await h.tick(1000);
 assert.equal(h.events.findLast(e=>e.type==='speaker').speaker.state,'confirming');h.capture.deleteSpeaker();await h.capture.stop();
});
test('settings change clears worklet window and rejects pre-change audio after registration',async()=>{
 const h=harness(),{node}=addNoiseReduction(h);node.vadStatus='ready';let calls=0;h.platform.createSpeakerEmbedding=()=>({embed:async()=>{calls++;return new Float32Array([1,0]);},cancel:()=>{}});
 h.track.getSettings=()=>({autoGainControl:false,noiseSuppression:false,echoCancellation:false});await h.capture.start();await h.capture.beginSpeakerEnrollment();node.port.onmessage({data:{type:'analysis',seq:0,sampleStart:0,sampleEnd:480,sampleTime:.01,power:.01,clipped:false,speech:'nonSpeech',meterRms:.1}});
 for(let i=0;i<3;i++){h.frame({},node);await h.tick(1000);node.port.onmessage({data:{type:'speaker_window',generation:1,pcm:new Float32Array(48000).fill(.01),sampleStart:i*48000,sampleEnd:(i+1)*48000,startTime:i,endTime:i+1,speechFrames:90,clipped:false}});await new Promise(setImmediate);}
 assert.equal(calls,3);h.track.getSettings=()=>({autoGainControl:true,noiseSuppression:false,echoCancellation:false});h.frame({},node);
 assert.deepEqual(node.port.messages.filter(x=>x.type==='speaker_capture').slice(-2).map(x=>x.enabled),[false,true]);
 node.port.onmessage({data:{type:'analysis',seq:300,sampleStart:144000,sampleEnd:144480,sampleTime:3.01,power:.01,clipped:false,speech:'nonSpeech',meterRms:.1}});
 const old=new Float32Array(48000).fill(.02);node.port.onmessage({data:{type:'speaker_window',generation:1,pcm:old,sampleStart:100800,sampleEnd:148800,startTime:2.1,endTime:3.1,speechFrames:90,clipped:false}});await new Promise(setImmediate);
 assert.equal(calls,3);assert.ok(old.every(x=>x===0));
 h.frame({},node);await h.tick(1000);
 const late=new Float32Array(48000).fill(.03);node.port.onmessage({data:{type:'speaker_window',generation:1,pcm:late,sampleStart:144000,sampleEnd:192000,startTime:3,endTime:4,speechFrames:90,clipped:false}});await new Promise(setImmediate);
 assert.equal(calls,3);assert.ok(late.every(x=>x===0));h.capture.deleteSpeaker();await h.capture.stop();
});
test('registered speaker resumes on a new capture but device change removes registration',async()=>{
 const h=harness(),{node}=addNoiseReduction(h);node.vadStatus='ready';h.platform.createSpeakerEmbedding=()=>({embed:async()=>new Float32Array([1,0]),cancel:()=>{}});
 await h.capture.start();await h.capture.beginSpeakerEnrollment();node.port.onmessage({data:{type:'analysis',seq:0,sampleStart:0,sampleEnd:480,sampleTime:.01,power:.01,clipped:false,speech:'nonSpeech',meterRms:.1}});
 for(let i=0;i<3;i++){h.frame({},node);await h.tick(1000);node.port.onmessage({data:{type:'speaker_window',generation:1,pcm:new Float32Array(48000).fill(.01),sampleStart:i*48000,sampleEnd:(i+1)*48000,startTime:i,endTime:i+1,speechFrames:90,clipped:false}});await new Promise(setImmediate);}
 assert.ok(h.events.some(e=>e.type==='speaker'&&e.speaker.state==='registered'));await h.capture.stop();
 const next=h.makeWorkletNode();next.vadStatus='ready';h.platform.createNoiseReductionNode=async()=>next;h.track.readyState='live';h.ctx.state='running';await h.capture.start();
 assert.ok(next.port.messages.some(x=>x.type==='speaker_capture'&&x.enabled));h.track.readyState='ended';await h.changeDevice();
 assert.equal(h.events.findLast(e=>e.type==='speaker').speaker.state,'unregistered');
});
test('deleting during registration prevents delayed completion and turns raw capture off',async()=>{
 const h=harness(),{node}=addNoiseReduction(h);node.vadStatus='ready';const delayed=deferred();h.platform.createSpeakerEmbedding=()=>({embed:()=>delayed.promise,cancel:()=>{}});
 await h.capture.start();await h.capture.beginSpeakerEnrollment();node.port.onmessage({data:{type:'analysis',seq:0,sampleStart:0,sampleEnd:480,sampleTime:.01,power:.01,clipped:false,speech:'nonSpeech',meterRms:.1}});
 h.frame({},node);await h.tick(1000);node.port.onmessage({data:{type:'speaker_window',generation:1,pcm:new Float32Array(48000).fill(.01),sampleStart:0,sampleEnd:48000,startTime:0,endTime:1,speechFrames:90,clipped:false}});await settle();
 h.capture.deleteSpeaker();delayed.resolve(new Float32Array([1,0]));await new Promise(setImmediate);
 assert.equal(h.events.findLast(e=>e.type==='speaker').speaker.state,'unregistered');assert.equal(node.port.messages.filter(x=>x.type==='speaker_capture').at(-1).enabled,false);await h.capture.stop();
});

test('successive input epochs use current speech immediately and preserve noise baseline', async () => {
  const h=harness(), {node}=addNoiseReduction(h);
  h.track.getSettings=()=>({autoGainControl:false,noiseSuppression:false,echoCancellation:false});
  await h.capture.start();
  const send=(seq,origin,speech,power=.01)=>node.port.onmessage({data:{type:'analysis',seq,sampleStart:seq*480,sampleEnd:(seq+1)*480,sampleTime:origin+(seq+1)/100,power,clipped:false,speech,meterRms:.5}});
  for(let i=0;i<400;i++){send(i,0,'nonSpeech');if(i%10===0)h.frame({},node);await h.tick(10);}
  assert.equal(h.events.findLast(e=>e.type==='analysis').analysis.state,'ready');
  for(let epoch=0;epoch<2;epoch++) {
    node.port.onmessage({data:{type:'analysis_reset'}});
    const origin=h.ctx.currentTime;
    for(let i=0;i<3;i++){send(i,origin,'speech');await h.tick(10);}
    assert.equal(h.events.findLast(e=>e.type==='analysis').analysis.meterState,'speech');
    send(3,origin,'nonSpeech'); await h.tick(10);
    assert.equal(h.events.findLast(e=>e.type==='analysis').analysis.meterState,'nonSpeech');
  }
  node.port.onmessage({data:{type:'analysis_reset'}});
  const origin=h.ctx.currentTime;
  for(let i=0;i<5000;i++){send(i,origin,'nonSpeech',.03);if(i%10===0)h.frame({},node);await h.tick(10);}
  assert.ok(h.events.findLast(e=>e.type==='analysis').analysis.offset>0);
  await h.capture.stop();
});

test('first non-speech frame after a gap clears previous speech', async () => {
  const h=harness(), {node}=addNoiseReduction(h);
  h.track.getSettings=()=>({autoGainControl:false,noiseSuppression:false,echoCancellation:false});
  await h.capture.start();
  const send=(seq,origin,speech)=>node.port.onmessage({data:{type:'analysis',seq,sampleStart:seq*480,sampleEnd:(seq+1)*480,sampleTime:origin+(seq+1)/100,power:.01,clipped:false,speech,meterRms:.5}});
  for(let i=0;i<400;i++){send(i,0,'nonSpeech');if(i%10===0)h.frame({},node);await h.tick(10);}
  for(let i=400;i<403;i++){send(i,0,'speech');await h.tick(10);}
  assert.equal(h.events.findLast(e=>e.type==='analysis').analysis.meterState,'speech');
  node.port.onmessage({data:{type:'analysis_reset'}});
  send(0,h.ctx.currentTime,'nonSpeech');
  const a=h.events.findLast(e=>e.type==='analysis').analysis;
  assert.equal(a.speech,'nonSpeech'); assert.equal(a.meterState,'nonSpeech'); assert.equal(a.meterDbfs,null);
  await h.capture.stop();
});

test('input gap invalidates meter and accepts a fresh sample-clock epoch', async () => {
  const h=harness(), {node}=addNoiseReduction(h);
  h.track.getSettings=()=>({echoCancellation:false});
  await h.capture.start();
  const send=(seq,origin)=>node.port.onmessage({data:{type:'analysis',seq,sampleStart:seq*480,sampleEnd:(seq+1)*480,sampleTime:origin+(seq+1)/100,power:.01,clipped:false,speech:'speech',meterRms:.5}});
  for(let i=0;i<5;i++){send(i,0);await h.tick(10);}
  assert.equal(h.events.findLast(e=>e.type==='analysis').analysis.meterState,'speech');
  node.port.onmessage({data:{type:'analysis_reset'}});
  assert.equal(h.events.findLast(e=>e.type==='analysis').analysis.meterState,'unavailable');
  await h.tick(1200);
  const origin=h.ctx.currentTime;
  for(let i=0;i<3;i++){send(i,origin);await h.tick(10);}
  const a=h.events.findLast(e=>e.type==='analysis').analysis;
  assert.equal(a.meterState,'speech');
  assert.equal(a.reason,'processing_settings');
  await h.capture.stop();
});

test('input gap keeps the session noise baseline but requires new evidence', async () => {
  const h=harness(), {node}=addNoiseReduction(h);
  h.track.getSettings=()=>({autoGainControl:false,noiseSuppression:false,echoCancellation:false});
  await h.capture.start();
  const send=(seq,origin,power)=>node.port.onmessage({data:{type:'analysis',seq,sampleStart:seq*480,sampleEnd:(seq+1)*480,sampleTime:origin+(seq+1)/100,power,clipped:false,speech:'nonSpeech',meterRms:.1}});
  for(let i=0;i<400;i++){send(i,0,.01);if(i%10===0)h.frame({},node);await h.tick(10);}
  assert.equal(h.events.findLast(e=>e.type==='analysis').analysis.state,'ready');
  node.port.onmessage({data:{type:'analysis_reset'}}); h.frame({},node); await h.tick(1000);
  const origin=h.ctx.currentTime;
  for(let i=0;i<5000;i++){send(i,origin,.03);if(i%10===0)h.frame({},node);await h.tick(10);}
  const a=h.events.findLast(e=>e.type==='analysis').analysis;
  assert.equal(a.state,'ready'); assert.ok(a.offset>0);
  await h.capture.stop();
});

for (const trackSettings of [
  {echoCancellation:false},
  {autoGainControl:true,noiseSuppression:false,echoCancellation:false},
  {autoGainControl:false,noiseSuppression:true,echoCancellation:false},
  {autoGainControl:false,noiseSuppression:false,echoCancellation:true},
]) test(`relative speech meter works while environment is held for ${JSON.stringify(trackSettings)}`, async () => {
  const h=harness(), {node}=addNoiseReduction(h);
  h.track.getSettings=()=>trackSettings;
  await h.capture.start();
  const published=h.events.findLast(e=>e.type==='settings').settings;
  if (!('autoGainControl' in trackSettings)) assert.equal('autoGainControl' in published,false);
  if (!('noiseSuppression' in trackSettings)) assert.equal('noiseSuppression' in published,false);
  const send=async(seq,speech,rms=.5)=>{node.port.onmessage({data:{type:'analysis',seq,sampleStart:seq*480,sampleEnd:(seq+1)*480,sampleTime:(seq+1)/100,power:.01,clipped:false,speech,meterRms:rms}});if(seq%10===0)h.frame({},node);await h.tick(10);return h.events.findLast(e=>e.type==='analysis').analysis;};
  assert.equal((await send(0,'speech')).meterState,'confirming');
  assert.equal((await send(1,'speech')).meterState,'confirming');
  let a=await send(2,'speech');
  assert.equal(a.meterState,'speech'); assert.equal(a.state,'unavailable');
  assert.equal(a.reason,'processing_settings'); assert.equal(a.noiseDbfs,null); assert.equal(a.offset,null);
  assert.equal((await send(3,'nonSpeech')).meterState,'nonSpeech');
  assert.equal((await send(4,'uncertain')).meterState,'uncertain');
  for(let seq=5;seq<3005;seq++) a=await send(seq,'speech');
  assert.equal(a.meterState,'speech'); assert.equal(a.state,'unavailable');
  h.frame({},node); await h.tick(250);
  assert.equal(h.events.findLast(e=>e.type==='analysis').analysis.meterState,'unavailable');
  await h.capture.stop();
});

test('processing setting changes reset relative speech onset evidence', async () => {
  const h=harness(), {node}=addNoiseReduction(h); let settings={echoCancellation:false};
  h.track.getSettings=()=>settings;
  await h.capture.start();
  const send=async(seq)=>{node.port.onmessage({data:{type:'analysis',seq,sampleStart:seq*480,sampleEnd:(seq+1)*480,sampleTime:(seq+1)/100,power:.01,clipped:false,speech:'speech',meterRms:.2}});await h.tick(10);return h.events.findLast(e=>e.type==='analysis').analysis;};
  await send(0); await send(1); assert.equal((await send(2)).meterState,'speech');
  settings={autoGainControl:true,noiseSuppression:false,echoCancellation:false};
  assert.equal((await send(3)).meterState,'confirming');
  await send(4); assert.equal((await send(5)).meterState,'speech');
  settings={autoGainControl:false,noiseSuppression:false,echoCancellation:false};
  const supported=await send(6);
  assert.equal(supported.state,'collecting'); assert.equal(supported.meterState,'confirming');
  node.port.onmessage({data:{type:'analysis_unavailable'}});
  assert.equal(h.events.findLast(e=>e.type==='analysis').analysis.meterState,'unavailable');
  await send(7); await send(8);
  assert.equal((await send(9)).meterState,'unavailable');
  await h.capture.stop();
  h.track.readyState='live'; h.ctx.state='running'; settings={echoCancellation:false};
  const next=addNoiseReduction(h); await h.capture.start();
  next.node.port.onmessage({data:{type:'analysis',seq:0,sampleStart:0,sampleEnd:480,sampleTime:h.ctx.currentTime+.01,power:.01,clipped:false,speech:'speech',meterRms:.2}});
  const restarted=h.events.findLast(e=>e.type==='analysis').analysis;
  assert.equal(restarted.meterState,'confirming'); assert.equal(restarted.state,'unavailable');
  await h.capture.stop();
});

test('stalled context resume after permission reports a recoverable error and releases track', async () => {
  const h=harness(), gate=deferred();
  h.ctx.state='suspended'; h.ctx.resume=()=>gate.promise;
  let timeout;
  h.platform.setTimeout=(fn,ms)=>{assert.equal(ms,5000);timeout=fn;return 9;};
  h.platform.clearTimeout=()=>{};
  const pending=h.capture.start(false);
  await settle();
  assert.equal(typeof timeout,'function');
  timeout(); await pending;
  assert.equal(h.events.at(-1).state,'error');
  assert.equal(h.events.at(-1).reason,'context_resume_timeout');
  assert.ok(h.track.stops>0);
  gate.resolve(); await settle();
  assert.notEqual(h.events.at(-1).state,'running');
});

test('context resume rejection has an actionable distinct reason', async () => {
  const h=harness(); h.ctx.resume=async()=>{throw new Error('blocked');};
  await h.capture.start(false);
  assert.equal(h.events.at(-1).reason,'context_resume_failed');
  assert.ok(h.track.stops>0);
});

test('synchronous resume failure reports the context error', async () => {
  const h=harness(); h.ctx.resume=()=>{throw new Error('blocked');};
  await h.capture.start(false);
  assert.equal(h.events.at(-1).reason,'context_resume_failed');
});

test('resolved resume with suspended context does not claim capture is running', async () => {
  const h=harness(); h.ctx.state='suspended'; h.ctx.resume=async()=>{};
  await h.capture.start(false);
  assert.equal(h.events.at(-1).reason,'context_not_running');
  assert.ok(h.track.stops>0);
});

test('resume begins before permission wait and cancellation clears its timeout', async () => {
  const h=harness(), permission=deferred(), resume=deferred(); let cleared=false, resumeCalled=false;
  h.ctx.state='suspended'; h.ctx.resume=()=>{resumeCalled=true;return resume.promise;};
  h.platform.getUserMedia=()=>{assert.equal(resumeCalled,true);return permission.promise;};
  h.platform.setTimeout=()=>9;
  h.platform.clearTimeout=id=>{assert.equal(id,9);cleared=true;};
  const pending=h.capture.start(false);
  permission.resolve(h.stream); await settle();
  await h.capture.stop(); await pending;
  assert.equal(cleared,true); assert.ok(h.track.stops>0);
  resume.resolve(); await settle();
  assert.notEqual(h.events.at(-1).state,'running');
});

test('settings include context state without exposing track identity', async () => {
  const h=harness();
  await h.capture.start(false);
  const settings=h.events.findLast(e=>e.type==='settings').settings;
  assert.equal(settings.contextState,'running');
  assert.equal('deviceId' in settings,false);
  await h.capture.stop();
});

test('unreadable track settings report their own failure reason', async () => {
  const h=harness(); h.track.getSettings=()=>{throw new Error('not available');};
  await h.capture.start(false);
  assert.equal(h.events.at(-1).reason,'settings_unavailable');
  assert.ok(h.track.stops>0);
});

test('context suspension is reported even when input frames stop', async () => {
  const h=harness(); await h.capture.start(false);
  h.ctx.state='suspended'; await h.tick(250);
  assert.equal(h.events.findLast(e=>e.type==='settings').settings.contextState,'suspended');
  await h.capture.stop();
});

test('synthetic 10–60ms speech decisions compare onset duration without an RMS threshold', async () => {
  for (let length=1;length<=6;length++) {
    const h=harness(), {node}=addNoiseReduction(h);
    h.track.getSettings=()=>({autoGainControl:false,noiseSuppression:false,echoCancellation:false});
    await h.capture.start();
    for(let seq=0;seq<length;seq++) {
      node.port.onmessage({data:{type:'analysis',seq,sampleStart:seq*480,sampleEnd:(seq+1)*480,sampleTime:(seq+1)/100,power:1e-8,clipped:false,speech:'speech',meterRms:.0001}});
      await h.tick(10);
    }
    assert.equal(h.events.some(e=>e.type==='analysis' && e.analysis.meterState==='speech'),length>=3,`frames=${length}`);
    await h.capture.stop();
  }
});

test('invalid frame and new session discard previous onset evidence', async () => {
  const h=harness(), {node}=addNoiseReduction(h);
  h.track.getSettings=()=>({autoGainControl:false,noiseSuppression:false,echoCancellation:false});
  await h.capture.start();
  const send=(seq,rms)=>node.port.onmessage({data:{type:'analysis',seq,sampleStart:seq*480,sampleEnd:(seq+1)*480,sampleTime:(seq+1)/100,power:.01,clipped:false,speech:'speech',meterRms:rms}});
  send(0,.1); await h.tick(10); send(1,.1); await h.tick(10); send(2,NaN);
  assert.equal(h.events.findLast(e=>e.type==='analysis').analysis.meterState,'unavailable');
  await h.tick(10); send(3,.1);
  assert.equal(h.events.findLast(e=>e.type==='analysis').analysis.meterState,'confirming');
  await h.capture.stop();
  h.track.readyState='live'; h.ctx.state='running';
  const next=addNoiseReduction(h); await h.capture.start();
  next.node.port.onmessage({data:{type:'analysis',seq:0,sampleStart:0,sampleEnd:480,sampleTime:h.ctx.currentTime+.01,power:.01,clipped:false,speech:'speech',meterRms:.1}});
  assert.equal(h.events.findLast(e=>e.type==='analysis').analysis.meterState,'confirming');
  await h.capture.stop();
});

test('speech onset requires three consecutive frames and uses only the latest RMS', async () => {
  const h=harness(), {node}=addNoiseReduction(h);
  h.track.getSettings=()=>({autoGainControl:false,noiseSuppression:false,echoCancellation:false});
  await h.capture.start();
  const send=async(seq,speech,rms)=>{node.port.onmessage({data:{type:'analysis',seq,sampleStart:seq*480,sampleEnd:(seq+1)*480,sampleTime:(seq+1)/100,power:.01,clipped:false,speech,meterRms:rms}});await h.tick(10);return h.events.findLast(e=>e.type==='analysis').analysis;};
  assert.equal((await send(0,'speech',.9)).meterState,'confirming');
  assert.equal((await send(1,'nonSpeech',.2)).meterState,'nonSpeech');
  assert.equal((await send(2,'speech',.9)).meterState,'confirming');
  assert.equal((await send(3,'speech',.8)).meterState,'confirming');
  const confirmed=await send(4,'speech',.02);
  assert.equal(confirmed.meterState,'speech');
  assert.ok(Math.abs(confirmed.meterDbfs-20*Math.log10(.02))<1e-9);
  assert.equal((await send(5,'uncertain',.5)).meterState,'uncertain');
  assert.equal((await send(6,'speech',.01)).meterState,'confirming');
  assert.equal((await send(7,'speech',.01)).meterState,'confirming');
  assert.equal((await send(8,'speech',.01)).meterState,'speech');
  await h.capture.stop();
});

test('speech confirmation resets on frame gap, settings change and stale input', async () => {
  const h=harness(), {node}=addNoiseReduction(h); let agc=false;
  h.track.getSettings=()=>({autoGainControl:agc,noiseSuppression:false,echoCancellation:false});
  await h.capture.start();
  const send=async(seq)=>{node.port.onmessage({data:{type:'analysis',seq,sampleStart:seq*480,sampleEnd:(seq+1)*480,sampleTime:(seq+1)/100,power:.01,clipped:false,speech:'speech',meterRms:.05}});await h.tick(10);return h.events.findLast(e=>e.type==='analysis').analysis;};
  await send(0); await send(1); assert.equal((await send(2)).meterState,'speech');
  await h.tick(10); assert.equal((await send(4)).meterState,'confirming');
  await send(5); assert.equal((await send(6)).meterState,'speech');
  agc=true; assert.equal((await send(7)).meterState,'confirming');
  agc=false; assert.equal((await send(8)).meterState,'confirming');
  await send(9); assert.equal((await send(10)).meterState,'speech');
  h.frame({},node); await h.tick(250);
  assert.equal(h.events.findLast(e=>e.type==='analysis').analysis.meterState,'unavailable');
  assert.equal((await send(36)).meterState,'confirming');
  await h.capture.stop();
});

for (const initialNoise of [false,true]) test(`continuous speech stays visible with ${initialNoise ? 'stale noise' : 'no initial noise'}`, async () => {
  const h=harness(), {node}=addNoiseReduction(h);
  h.track.getSettings=()=>({autoGainControl:false,noiseSuppression:false,echoCancellation:false});
  await h.capture.start();
  const send=(seq,speech)=>node.port.onmessage({data:{type:'analysis',seq,sampleStart:seq*480,sampleEnd:(seq+1)*480,sampleTime:(seq+1)/100,power:.01,clipped:false,speech,meterRms:.5}});
  for(let seq=0;seq<(initialNoise?400:0);seq++){send(seq,'nonSpeech');if(seq%10===0)h.frame({},node);await h.tick(10);}
  const start=initialNoise?400:0;
  for(let seq=start;seq<start+3000;seq++){send(seq,'speech');if(seq%10===0)h.frame({},node);await h.tick(10);}
  const a=h.events.findLast(e=>e.type==='analysis').analysis;
  assert.equal(a.state, initialNoise?'held':'collecting');
  assert.equal(a.meterState,'speech');
  assert.ok(Math.abs(a.meterDbfs-20*Math.log10(.5))<1e-9);
  h.frame({},node); await h.tick(250);
  assert.equal(h.events.findLast(e=>e.type==='analysis').analysis.meterState,'unavailable');
  await h.capture.stop();
});

test('speech meter follows the matching fresh analysis frame and clears immediately', async () => {
  const h=harness(), {node}=addNoiseReduction(h);
  h.track.getSettings=()=>({autoGainControl:false,noiseSuppression:false,echoCancellation:false});
  await h.capture.start();
  const send=(seq,speech,meterRms)=>node.port.onmessage({data:{type:'analysis',seq,sampleStart:seq*480,sampleEnd:(seq+1)*480,sampleTime:(seq+1)/100,power:.01,clipped:false,speech,meterRms}});
  for(let i=0;i<400;i++){send(i,'nonSpeech',.1);if(i%10===0)h.frame({},node);await h.tick(10);}
  h.frame({rms:.01,dbfs:-40},node);
  send(400,'speech',.5);
  await h.tick(10); send(401,'speech',.5);
  await h.tick(10); send(402,'speech',.5);
  let a=h.events.findLast(e=>e.type==='analysis').analysis;
  assert.equal(a.speech,'speech'); assert.ok(Math.abs(a.meterDbfs-20*Math.log10(.5))<1e-9);
  h.frame({rms:.9,dbfs:-1},node);
  assert.equal(h.events.findLast(e=>e.type==='analysis').analysis.meterDbfs,a.meterDbfs);
  await h.tick(10); send(403,'nonSpeech',.9);
  a=h.events.findLast(e=>e.type==='analysis').analysis;
  assert.equal(a.speech,'nonSpeech'); assert.equal(a.meterState,'nonSpeech'); assert.equal(a.meterDbfs,null);
  await h.tick(10); send(404,'uncertain',.9);
  assert.equal(h.events.findLast(e=>e.type==='analysis').analysis.meterState,'uncertain');
  assert.equal(h.events.findLast(e=>e.type==='analysis').analysis.meterDbfs,null);
  await h.tick(10); send(405,'speech',.7);
  await h.tick(10); send(406,'speech',.7);
  await h.tick(10); send(407,'speech',.7);
  assert.ok(h.events.findLast(e=>e.type==='analysis').analysis.meterDbfs != null);
  h.frame({},node); await h.tick(250);
  assert.equal(h.events.findLast(e=>e.type==='analysis').analysis.state,'held');
  assert.equal(h.events.findLast(e=>e.type==='analysis').analysis.meterDbfs,undefined);
  await h.capture.stop();
});

test('VAD runtime failure remains in settings after processing settings change', async () => {
  const h=harness(), {node}=addNoiseReduction(h);
  node.vadStatus='ready';
  let agc=false;
  h.track.getSettings=()=>({autoGainControl:agc,noiseSuppression:false,echoCancellation:false});
  await h.capture.start();
  node.port.onmessage({data:{type:'analysis_unavailable'}});
  agc=true;
  h.frame({},node);
  assert.equal(h.events.findLast(e=>e.type==='settings').settings.vadStatus,'runtime_failed');
  await h.capture.stop();
});

test('capture publishes VAD initialization status without device identity', async () => {
  const h=harness(), noise=addNoiseReduction(h);
  noise.node.vadStatus='init_failed';
  h.track.getSettings=()=>({deviceId:'private',autoGainControl:false,noiseSuppression:false,echoCancellation:false});
  await h.capture.start();
  const settings=h.events.findLast(e=>e.type==='settings').settings;
  assert.equal(settings.vadStatus,'init_failed');
  assert.equal('deviceId' in settings,false);
  await h.capture.stop();
});

test('analysis only accepts fresh frames when processing settings are known disabled', async () => {
  const h=harness(), noise=addNoiseReduction(h);
  h.track.getSettings=()=>({sampleRate:48000,autoGainControl:false,noiseSuppression:false,echoCancellation:false});
  await h.capture.start();
  const node=noise.node;
  for(let seq=0;seq<410;seq++) {
    node.port.onmessage({data:{type:'analysis',seq,sampleStart:seq*480,sampleEnd:(seq+1)*480,sampleTime:(seq+1)/100,power:.01,clipped:false,speech:'nonSpeech'}});
    if (seq%10===0) h.frame({},node);
    await h.tick(10);
  }
  assert.equal(h.events.findLast(e=>e.type==='analysis').analysis.state,'ready');
  h.track.getSettings=()=>({sampleRate:48000,autoGainControl:true,noiseSuppression:false,echoCancellation:false});
  node.port.onmessage({data:{type:'analysis',seq:410,sampleStart:196800,sampleEnd:197280,sampleTime:4.11,power:.01,clipped:false,speech:'nonSpeech'}});
  assert.equal(h.events.findLast(e=>e.type==='analysis').analysis.state,'unavailable');
  assert.equal(h.events.findLast(e=>e.type==='analysis').analysis.reason,'processing_settings');
  await h.capture.stop();
});

test('backlog stays held until audio clock catches up and preserves initial baseline', async () => {
  const h=harness(), {node}=addNoiseReduction(h);
  h.track.getSettings=()=>({autoGainControl:false,noiseSuppression:false,echoCancellation:false});
  await h.capture.start();
  const send=(seq,power)=>node.port.onmessage({data:{type:'analysis',seq,sampleStart:seq*480,sampleEnd:(seq+1)*480,sampleTime:(seq+1)/100,power,clipped:false,speech:'nonSpeech'}});
  for(let seq=0;seq<400;seq++){send(seq,.01);if(seq%10===0)h.frame({},node);await h.tick(10);}
  for(let i=0;i<20;i++){h.frame({},node);await h.tick(100);}
  for(let seq=400;seq<900;seq++){send(seq,.03);if(seq%10===0)h.frame({},node);await h.tick(10);}
  assert.equal(h.events.findLast(e=>e.type==='analysis').analysis.state,'held');
  for(let seq=1100;seq<4500;seq++){send(seq,.03);if(seq%10===0)h.frame({},node);await h.tick(10);}
  assert.ok(h.events.findLast(e=>e.type==='analysis').analysis.offset > 0);
  await h.capture.stop();
});
function assertReleased(h){assert.ok(h.track.stops>=1);assert.equal(h.ctx.state,'closed');assert.equal(h.port.onmessage,null);assert.equal(h.timers.size,0);}

test('disabled_noise_reduction_skips_loader_and_measures_raw_input', async () => {
  const h=harness(); let loadCount=0;
  h.platform.createNoiseReductionNode=async()=>{loadCount++;return h.makeWorkletNode();};
  await h.capture.start(false);
  assert.equal(loadCount,0);
  assert.equal(h.events.findLast(e=>e.type==='settings').settings.noiseReductionState,'disabled');
  assert.equal(h.events.some(e=>e.settings?.noiseReductionState==='loading'),false);
  assert.equal(h.events.at(-1).state,'running');
  h.frame({dbfs:-35});
  assert.equal(h.events.at(-1).dbfs,-35);
  await h.capture.stop(); assertReleased(h);
});

test('disabled_noise_reduction_does_not_report_unavailable_without_a_loader', async () => {
  const h=harness(); await h.capture.start(false);
  const settings=h.events.findLast(e=>e.type==='settings').settings;
  assert.equal(settings.noiseReductionState,'disabled');
  assert.equal(settings.noiseReductionReason,undefined);
  await h.capture.stop(); assertReleased(h);
});

test('switch_to_raw_input_survives_previous_context_closing_late', async () => {
  const h=harness(), noise=addNoiseReduction(h), next=harness(), closing=deferred();
  h.ctx.close=async()=>{await closing.promise;h.ctx.state='closed';};
  await h.capture.start();
  const stale=noise.node.port.onmessage;
  const stopped=h.capture.stop();
  assert.equal(h.track.readyState,'ended');
  for (const key of ['createContext','getUserMedia','createWorkletNode']) h.platform[key]=next.platform[key];
  await h.capture.start(false);
  assert.equal(h.events.findLast(e=>e.type==='settings').settings.noiseReductionState,'disabled');
  next.frame({dbfs:-30});
  assert.equal(h.events.at(-1).dbfs,-30);
  const count=h.events.length;
  stale({data:{type:'level',rms:.5,peak:.5,dbfs:-6,normalized:.9,sampleCount:4800}});
  assert.equal(h.events.length,count);
  closing.resolve(); await stopped;
  assert.equal(next.ctx.state,'running');
  assert.equal(next.track.readyState,'live');
  next.frame({dbfs:-25});
  assert.equal(h.events.at(-1).dbfs,-25);
  await h.capture.stop(); assertReleased(next);
});

test('noise_factory_deadline_includes_module_loading_and_disposes_late_node', async t => {
  t.mock.timers.enable({apis:['setTimeout']});
  const h=harness(), gate=deferred(), late=h.makeWorkletNode(); let signal;
  h.platform.createNoiseReductionNode=(_context, value)=>{signal=value;return gate.promise;};
  t.after(async()=>{gate.resolve(late);await h.capture.stop();});
  const pending=h.capture.start(); await settle();
  t.mock.timers.tick(10000); await settle();
  assert.equal(h.events.at(-1)?.state,'running');
  assert.equal(h.events.findLast(e=>e.type==='settings').settings.noiseReductionReason,'load_timeout');
  assert.equal(signal.aborted,true);
  gate.resolve(late); await pending; await settle();
  assert.equal(late.port.closed,true); assert.equal(late.disconnected,true);
  h.frame(); assert.equal(h.events.at(-1).type,'level');
});

test('cancel_does_not_wait_for_a_stalled_noise_factory_or_revive_its_late_node', async t => {
  const h=harness(), gate=deferred(), late=h.makeWorkletNode(); let completed=false;
  h.platform.createNoiseReductionNode=()=>gate.promise;
  t.after(()=>gate.resolve(late));
  const pending=h.capture.start().then(()=>{completed=true;}); await settle();
  await h.capture.stop(); await settle();
  assert.equal(completed,true);
  gate.resolve(late); await pending; await settle();
  assert.equal(late.port.closed,true); assert.equal(late.disconnected,true);
  assert.equal(h.events.some(e=>e.state==='running'),false); assertReleased(h);
});

test('stop_before_permission_resolves_stops_late_tracks',async()=>{
  const p=deferred(),h=harness({permission:p}); const pending=h.capture.start();
  await h.capture.stop();p.resolve(h.stream);await pending;
  assertReleased(h);assert.equal(h.events.filter(e=>e.state==='running').length,0);
});
test('double_start_has_one_stream',async()=>{
  const p=deferred(),h=harness({permission:p});const a=h.capture.start(),b=h.capture.start();p.resolve(h.stream);await Promise.all([a,b]);
  assert.equal(h.platform.calls,1);assert.equal(h.events.filter(e=>e.state==='running').length,1);await h.capture.stop();
});
test('stop_clears_audio_and_callbacks',async()=>{
  const h=harness();await h.capture.start();h.frame();const stale=h.port.onmessage;await h.capture.stop();
  stale({data:{type:'level',rms:.5,peak:.5,dbfs:-6,normalized:.9,sampleCount:4800}});h.frame();assertReleased(h);
  assert.equal(h.events.filter(e=>e.type==='level').length,1);assert.ok(h.nodes.every(n=>n.disconnected));
});
for(const [name,reason] of [['NotAllowedError','permission_denied'],['NotFoundError','device_missing'],['NotReadableError','device_busy']]) test(`${reason}_maps_to_error`,async()=>{
  const h=harness();h.platform.getUserMedia=async()=>{throw Object.assign(new Error(),{name});};await h.capture.start();
  assert.deepEqual(h.events.at(-1),{type:'state',state:'error',reason});assert.equal(h.ctx.state,'closed');
});
for(const name of ['mute','ended']) test(`${name}_stops_capture`,async()=>{
  const h=harness();await h.capture.start();h.track.dispatchEvent(new Event(name));await settle();assertReleased(h);assert.equal(h.events.at(-1).reason,`input_${name==='mute'?'muted':'ended'}`);
});
test('hidden_tab_stops_capture',async()=>{const h=harness();await h.capture.start();await h.hide();assertReleased(h);assert.equal(h.events.at(-1).reason,'tab_hidden');});
test('no_frame_for_1500ms_stops_capture',async()=>{const h=harness();await h.capture.start();await h.tick(1499);assert.equal(h.track.stops,0);await h.tick(1);assertReleased(h);assert.equal(h.events.at(-1).reason,'frame_timeout');});
test('frames_reset_timeout',async()=>{const h=harness();await h.capture.start();await h.tick(1000);h.frame();await h.tick(1000);assert.equal(h.track.stops,0);await h.capture.stop();});
test('stop_while_worklet_loads_releases_stream_and_context',async()=>{const gate=deferred(),h=harness({moduleGate:gate});const pending=h.capture.start();await settle();await h.capture.stop();gate.resolve();await pending;assertReleased(h);assert.equal(h.events.filter(e=>e.state==='running').length,0);});
test('invalid_frame_ends_capture',async()=>{const h=harness();await h.capture.start();h.port.onmessage({data:{type:'level',rms:NaN,dbfs:null,normalized:0,sampleCount:4800}});await settle();assertReleased(h);assert.equal(h.events.at(-1).reason,'invalid_samples');});
test('processor_failure_ends_capture',async()=>{const h=harness();await h.capture.start();h.node.onprocessorerror();await settle();assertReleased(h);assert.equal(h.events.at(-1).reason,'processing_error');});
test('muted_track_on_start_is_not_running',async()=>{const h=harness();h.track.muted=true;await h.capture.start();assertReleased(h);assert.equal(h.events.at(-1).reason,'input_muted');});

test('peak_above_full_scale_reaches_the_level_consumer', async () => {
  const h=harness(); await h.capture.start(); h.frame({peak:1.25});
  assert.equal(h.events.at(-1).type, 'level');
  assert.equal(h.events.at(-1).peak, 1.25);
  await h.capture.stop();
});

for (const peak of [undefined, NaN, Infinity, -.01]) test(`invalid_peak_${String(peak)}_ends_capture`, async () => {
  const h=harness(); await h.capture.start(); h.frame({peak}); await settle();
  assertReleased(h); assert.equal(h.events.at(-1).reason, 'invalid_samples');
});

test('device_change_stops_capture_and_releases_its_subscription', async () => {
  const h=harness(); await h.capture.start(); h.frame(); await h.changeDevice();
  assertReleased(h);
  assert.deepEqual(h.events.at(-1), {type:'state',state:'idle',reason:'device_changed'});
  assert.equal(h.deviceListeners.size, 0);
  const eventCount=h.events.length;
  await h.changeDevice(); h.frame();
  assert.equal(h.events.length, eventCount);
});

test('device_list_exposure_during_permission_does_not_cancel_the_selected_stream', async () => {
  const permission=deferred(), h=harness({permission});
  const pending=h.capture.start(); await h.changeDevice();
  assert.deepEqual(h.events.at(-1), {type:'state',state:'requesting'});
  permission.resolve(h.stream); await pending;
  h.frame(); assert.equal(h.events.at(-1).type,'level');
  await h.capture.stop(); assertReleased(h);
});

test('startup_device_notification_without_identity_does_not_cancel_before_audio', async () => {
  const h=harness(); await h.capture.start(false); await h.changeDevice();
  assert.equal(h.track.stops,0); h.frame();
  assert.equal(h.events.at(-1).type,'level');
  await h.capture.stop(); assertReleased(h);
});

test('unchanged_active_microphone_survives_device_list_notifications_without_exposing_id', async () => {
  const h=harness(); h.track.getSettings=()=>({sampleRate:48000,deviceId:'private-built-in'});
  await h.capture.start(false); h.frame(); await h.changeDevice(); h.frame();
  assert.equal(h.track.stops,0); assert.equal(h.events.at(-1).type,'level');
  assert.equal(JSON.stringify(h.events).includes('private-built-in'),false);
  await h.capture.stop(); assertReleased(h);
});

test('changed_active_microphone_still_stops_before_or_after_first_audio', async () => {
  for(const hasFrame of [false,true]) {
    const h=harness(); let deviceId='built-in';
    h.track.getSettings=()=>({sampleRate:48000,deviceId});
    await h.capture.start(false); if(hasFrame) h.frame();
    deviceId='headset'; await h.changeDevice();
    assert.equal(h.events.at(-1).reason,'device_changed'); assertReleased(h);
  }
});

test('newly_exposed_identity_is_baselined_only_before_audio', async () => {
  for(const hasFrame of [false,true]) {
    const h=harness(); let deviceId;
    h.track.getSettings=()=>({sampleRate:48000,deviceId});
    await h.capture.start(false); if(hasFrame) h.frame();
    deviceId='built-in'; await h.changeDevice();
    if(hasFrame) { assert.equal(h.events.at(-1).reason,'device_changed'); assertReleased(h); }
    else { h.frame(); await h.changeDevice(); assert.equal(h.track.stops,0); await h.capture.stop(); }
  }
});

test('unreadable_or_inactive_track_is_not_ignored_on_device_notification', async () => {
  for(const state of ['ended','muted','settings_error']) {
    const h=harness(); h.track.getSettings=()=>({sampleRate:48000,deviceId:'built-in'});
    await h.capture.start(false);
    if(state==='ended') h.track.readyState='ended';
    else if(state==='muted') h.track.muted=true;
    else h.track.getSettings=()=>{throw new Error('read failed');};
    await h.changeDevice(); assertReleased(h);
    assert.equal(h.events.at(-1).reason,state==='settings_error'?'settings_unavailable':'device_changed');
  }
});

test('explicit_stop_removes_device_listener_and_suppresses_late_callback', async () => {
  const h=harness(); await h.capture.start();
  assert.equal(h.deviceListeners.size, 1);
  const stale=[...h.deviceListeners][0];
  await h.capture.stop(); const eventCount=h.events.length;
  assert.equal(h.deviceListeners.size, 0);
  stale(); await settle();
  assert.equal(h.events.length, eventCount);
});

test('capture_failure_removes_device_listener', async () => {
  const h=harness(); await h.capture.start();
  assert.equal(h.deviceListeners.size, 1);
  h.node.onprocessorerror(); await settle();
  assert.equal(h.deviceListeners.size, 0);
  const eventCount=h.events.length; await h.changeDevice();
  assert.equal(h.events.length, eventCount);
});

test('platform_without_device_change_support_still_captures', async () => {
  const h=harness(); delete h.platform.subscribeDeviceChange;
  await h.capture.start(); h.frame();
  assert.equal(h.events.at(-1).type, 'level');
  await h.capture.stop(); assertReleased(h);
});

test('processing_setting_change_is_reported_before_the_next_level', async () => {
  const h=harness();
  let autoGainControl=false;
  h.track.getSettings=()=>({sampleRate:48000,autoGainControl,echoCancellation:false,deviceId:'private-device',groupId:'private-group'});
  await h.capture.start();
  autoGainControl=true; h.frame();
  const settingsEvents=h.events.filter(event=>event.type==='settings');
  assert.equal(settingsEvents.length, 2);
  assert.deepEqual(h.events.at(-2), {type:'settings',settings:{contextSampleRate:48000,contextState:'running',sampleRate:48000,autoGainControl:true,echoCancellation:false,noiseReductionState:'unavailable',speakerAvailable:false,noiseReductionReason:'unsupported'}});
  assert.equal(h.events.at(-1).type, 'level');
  h.frame();
  assert.equal(h.events.filter(event=>event.type==='settings').length, 2);
  await h.capture.stop();
});

test('processing_setting_disappearance_is_reported', async () => {
  const h=harness(); await h.capture.start();
  h.track.getSettings=()=>({sampleRate:48000}); h.frame();
  assert.deepEqual(h.events.at(-2), {type:'settings',settings:{contextSampleRate:48000,contextState:'running',sampleRate:48000,noiseReductionState:'unavailable',speakerAvailable:false,noiseReductionReason:'unsupported'}});
  await h.capture.stop();
});

test('settings_read_failure_during_capture_stops_input', async () => {
  const h=harness(); await h.capture.start();
  h.track.getSettings=()=>{throw new Error('Track settings unavailable');};
  h.frame(); await settle();
  assertReleased(h);
  assert.equal(h.events.at(-1).reason, 'settings_unavailable');
});

test('insecure_context_rejects_before_requesting_microphone_access', async () => {
  const h=harness(); h.platform.isSecureContext=()=>false;
  await h.capture.start();
  assert.deepEqual(h.events.at(-1), {type:'state',state:'error',reason:'insecure_context'});
  assert.equal(h.platform.calls, 0);
  assert.equal(h.deviceListeners.size, 0);
});

test('secure_context_keeps_capture_available', async () => {
  const h=harness(); h.platform.isSecureContext=()=>true;
  await h.capture.start(); h.frame();
  assert.equal(h.events.at(-1).type, 'level');
  await h.capture.stop();
});

test('default_platform_without_browser_media_apis_reports_unsupported', async () => {
  const events=[];
  const capture=createCapture({onEvent:event=>events.push(event)});
  await capture.start();
  assert.deepEqual(events.at(-1), {type:'state',state:'error',reason:'unsupported'});
});

test('missing_worklet_constructor_rejects_before_requesting_microphone_access', async () => {
  const h=harness(); delete h.platform.createWorkletNode;
  await h.capture.start();
  assert.deepEqual(h.events.at(-1), {type:'state',state:'error',reason:'unsupported'});
  assert.equal(h.platform.calls, 0);
});

function addNoiseReduction(h, {gate, error}={}) {
  const node=h.makeWorkletNode(); let signal;
  h.platform.createNoiseReductionNode=async (context, abortSignal)=>{
    assert.equal(context,h.ctx); signal=abortSignal;
    if(gate) await gate.promise;
    if(error) throw error;
    return node;
  };
  return {node,get signal(){return signal;}};
}

test('missing_noise_reduction_reports_raw_input_before_running', async () => {
  const h=harness(); await h.capture.start(); h.frame();
  const setting=h.events.find(event=>event.type==='settings');
  assert.equal(setting.settings.noiseReductionState,'unavailable');
  assert.equal(setting.settings.noiseReductionReason,'unsupported');
  assert.ok(h.events.indexOf(setting)<h.events.findIndex(event=>event.state==='running'));
  assert.equal(h.events.at(-1).type,'level');
  await h.capture.stop();
});

test('noise_reduction_loading_waits_without_a_frame_timeout_then_measures_filtered_input', async () => {
  const h=harness(), gate=deferred(), noise=addNoiseReduction(h,{gate});
  const pending=h.capture.start(); await settle();
  assert.equal(h.events.at(-1).settings?.noiseReductionState,'loading');
  assert.equal(h.events.some(event=>event.state==='running'),false);
  assert.equal(h.timers.size,0);
  await h.tick(3000);
  assert.equal(h.track.stops,0);
  gate.resolve(); await pending;
  assert.deepEqual(h.events.filter(event=>event.type==='settings').map(event=>event.settings.noiseReductionState),['loading','active']);
  assert.equal(h.node.connections.length,0);
  assert.ok(h.nodes.some(node=>node.connections.includes(noise.node)));
  h.frame({dbfs:-20},noise.node);
  assert.equal(h.events.at(-1).dbfs,-20);
  await h.tick(1500);
  assert.equal(h.events.at(-1).reason,'frame_timeout');
  assert.equal(noise.signal.aborted,true);
  assert.equal(noise.node.port.closed,true);
  assert.equal(noise.node.disconnected,true);
  assert.deepEqual(noise.node.port.messages,[{type:'dispose'}]);
});

for(const action of ['stop','hide','changeDevice']) test(`noise_reduction_${action}_while_loading_releases_a_late_node`, async () => {
  const h=harness(), gate=deferred(), noise=addNoiseReduction(h,{gate});
  let deviceId='built-in'; h.track.getSettings=()=>({sampleRate:48000,deviceId});
  const pending=h.capture.start(); await settle();
  assert.ok(noise.signal instanceof AbortSignal);
  if(action==='changeDevice') deviceId='headset';
  if(action==='stop') await h.capture.stop(); else await h[action]();
  assert.equal(noise.signal.aborted,true);
  const eventCount=h.events.length;
  gate.resolve(); await pending; await settle();
  assert.equal(h.events.length,eventCount);
  assert.equal(h.events.some(event=>event.state==='running'),false);
  assert.equal(noise.node.port.closed,true);
  assert.equal(noise.node.disconnected,true);
  assert.deepEqual(noise.node.port.messages,[{type:'dispose'}]);
  assertReleased(h);
});

test('late_noise_reduction_failure_after_stop_cannot_emit_fallback_or_revive_capture', async () => {
  const h=harness(), gate=deferred(), noise=addNoiseReduction(h,{gate});
  const pending=h.capture.start(); await settle();
  assert.ok(noise.signal instanceof AbortSignal);
  await h.capture.stop();
  const eventCount=h.events.length;
  gate.reject(new Error('load failed')); await pending;
  assert.equal(h.events.length,eventCount);
  assert.equal(h.events.some(event=>event.state==='running'),false);
  assertReleased(h);
});

for(const [captureReason,want] of [[undefined,'load_failed'],['unsupported_sample_rate','unsupported_sample_rate'],['internal path or token','load_failed']]) {
  test(`noise_reduction_load_failure_${want}_${String(captureReason)}_falls_back_to_raw`, async () => {
    const h=harness(); addNoiseReduction(h,{error:Object.assign(new Error('private error'),{captureReason})});
    await h.capture.start(); h.frame();
    const settings=h.events.filter(event=>event.type==='settings');
    assert.equal(settings[0].settings.noiseReductionState,'loading');
    assert.equal(settings.at(-1).settings.noiseReductionState,'unavailable');
    assert.equal(settings.at(-1).settings.noiseReductionReason,want);
    assert.equal(h.events.some(event=>event.state==='error'),false);
    assert.equal(h.events.at(-1).type,'level');
    assert.ok(h.nodes.some(node=>node.connections.includes(h.node)));
    await h.capture.stop(); assertReleased(h);
  });
}

test('noise_reduction_status_survives_browser_processing_setting_changes', async () => {
  const h=harness(), noise=addNoiseReduction(h); await h.capture.start();
  h.track.getSettings=()=>({autoGainControl:true,noiseSuppression:false});
  h.frame({},noise.node);
  assert.deepEqual(h.events.at(-2),{type:'settings',settings:{contextSampleRate:48000,contextState:'running',autoGainControl:true,noiseSuppression:false,noiseReductionState:'active',speakerAvailable:false}});
  assert.equal(h.events.at(-1).type,'level');
  await h.capture.stop();
});

for(const kind of ['message','processor']) test(`noise_reduction_runtime_${kind}_failure_stops_instead_of_silently_switching_input`, async () => {
  const h=harness(), noise=addNoiseReduction(h); await h.capture.start();
  h.frame({},noise.node);
  const stale=noise.node.port.onmessage;
  assert.equal(typeof stale,'function');
  assert.equal(typeof noise.node.onprocessorerror,'function');
  if(kind==='message') noise.node.port.onmessage({data:{type:'error'}}); else noise.node.onprocessorerror();
  await settle();
  assert.deepEqual(h.events.at(-1),{type:'state',state:'error',reason:'noise_reduction_failed'});
  assert.equal(noise.signal.aborted,true);
  assert.equal(noise.node.port.closed,true);
  assert.equal(noise.node.disconnected,true);
  assertReleased(h);
  const eventCount=h.events.length;
  stale({data:{type:'level',rms:.5,peak:.5,dbfs:-6,normalized:.9,sampleCount:4800}});
  assert.equal(h.events.length,eventCount);
});

test('noise_reduction_dispose_message_failure_does_not_leak_tracks_or_context', async () => {
  const h=harness(), noise=addNoiseReduction(h); await h.capture.start();
  noise.node.port.postMessage=()=>{throw new Error('port already closed');};
  await h.capture.stop();
  assert.equal(noise.node.port.closed,true);
  assert.equal(noise.node.disconnected,true);
  assertReleased(h);
});

for(const rejectPreferredRate of [false,true]) test(`browser_context_requests_48khz_and_default_fallback_${rejectPreferredRate}`, async t => {
  const h=harness(), attempts=[], document=new EventTarget(); document.hidden=false;
  const mediaDevices=new EventTarget();
  mediaDevices.getUserMedia=async()=>{throw Object.assign(new Error(),{name:'NotAllowedError'});};
  const replacements={
    navigator:{mediaDevices},
    document,
    AudioWorkletNode:class {},
    AudioContext:class { constructor(options){attempts.push(options);if(rejectPreferredRate&&options)throw new Error('rate unsupported');return h.ctx;} },
  };
  for(const [key,value] of Object.entries(replacements)) {
    const descriptor=Object.getOwnPropertyDescriptor(globalThis,key);
    Object.defineProperty(globalThis,key,{configurable:true,writable:true,value});
    t.after(()=>{if(descriptor)Object.defineProperty(globalThis,key,descriptor);else delete globalThis[key];});
  }
  const events=[]; await createCapture({onEvent:event=>events.push(event)}).start();
  assert.deepEqual(attempts,rejectPreferredRate?[{sampleRate:48000},undefined]:[{sampleRate:48000}]);
  assert.deepEqual(events.at(-1),{type:'state',state:'error',reason:'permission_denied'});
  assert.equal(h.ctx.closed,1);
});
