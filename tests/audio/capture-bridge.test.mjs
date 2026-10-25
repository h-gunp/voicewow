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
  const ctx={state:'running',sampleRate:48000,destination:{},closed:0,resume:async()=>{},close:async()=>{ctx.closed++;ctx.state='closed';},audioWorklet:{addModule:async()=>{if(moduleGate)await moduleGate.promise;}},createMediaStreamSource:()=>makeNode(),createGain:()=>Object.assign(makeNode(),{gain:{value:1}})};
  const makeWorkletNode=()=>Object.assign(makeNode(),{port:{onmessage:null,closed:false,messages:[],postMessage(message){this.messages.push(message);},close(){this.closed=true;}},onprocessorerror:null});
  const node=makeWorkletNode(), port=node.port;
  const platform={calls:0,getUserMedia:async()=>{platform.calls++;return permission?permission.promise:stream;},createContext:()=>ctx,createWorkletNode:()=>node,now:()=>time,setInterval:fn=>{timers.set(1,fn);return 1;},clearInterval:id=>timers.delete(id),isHidden:()=>hidden,subscribeVisibility:fn=>{visibility=fn;return()=>{visibility=null;};},subscribeDeviceChange:fn=>{deviceListeners.add(fn);return()=>deviceListeners.delete(fn);}};
  const capture=createCapture({onEvent:e=>events.push(e),platform});
  return {capture,platform,ctx,track,stream,node,port,nodes,timers,events,deviceListeners,makeWorkletNode,frame(overrides={},target=node){target.port.onmessage?.({data:{type:'level',rms:.5,peak:.5,dbfs:-6.0206,normalized:.925,sampleCount:4800,...overrides}});},async changeDevice(){for(const fn of [...deviceListeners])fn();await settle();},async hide(){hidden=true;visibility?.();await settle();},async tick(ms){time+=ms;for(const fn of timers.values())fn();await settle();}};
}
async function settle(){for(let i=0;i<8;i++)await Promise.resolve();}
function assertReleased(h){assert.ok(h.track.stops>=1);assert.equal(h.ctx.state,'closed');assert.equal(h.port.onmessage,null);assert.equal(h.timers.size,0);}

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

test('device_change_during_permission_wait_cannot_revive_late_stream', async () => {
  const permission=deferred(), h=harness({permission});
  const pending=h.capture.start(); await h.changeDevice();
  assert.deepEqual(h.events.at(-1), {type:'state',state:'idle',reason:'device_changed'});
  permission.resolve(h.stream); await pending;
  assertReleased(h);
  assert.equal(h.events.some(event=>event.state==='running'), false);
  assert.equal(h.deviceListeners.size, 0);
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
  assert.deepEqual(h.events.at(-2), {type:'settings',settings:{contextSampleRate:48000,sampleRate:48000,autoGainControl:true,echoCancellation:false,noiseReductionState:'unavailable',noiseReductionReason:'unsupported'}});
  assert.equal(h.events.at(-1).type, 'level');
  h.frame();
  assert.equal(h.events.filter(event=>event.type==='settings').length, 2);
  await h.capture.stop();
});

test('processing_setting_disappearance_is_reported', async () => {
  const h=harness(); await h.capture.start();
  h.track.getSettings=()=>({sampleRate:48000}); h.frame();
  assert.deepEqual(h.events.at(-2), {type:'settings',settings:{contextSampleRate:48000,sampleRate:48000,noiseReductionState:'unavailable',noiseReductionReason:'unsupported'}});
  await h.capture.stop();
});

test('settings_read_failure_during_capture_stops_input', async () => {
  const h=harness(); await h.capture.start();
  h.track.getSettings=()=>{throw new Error('Track settings unavailable');};
  h.frame(); await settle();
  assertReleased(h);
  assert.equal(h.events.at(-1).reason, 'processing_error');
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
  const pending=h.capture.start(); await settle();
  assert.ok(noise.signal instanceof AbortSignal);
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
  assert.deepEqual(h.events.at(-2),{type:'settings',settings:{contextSampleRate:48000,autoGainControl:true,noiseSuppression:false,noiseReductionState:'active'}});
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
