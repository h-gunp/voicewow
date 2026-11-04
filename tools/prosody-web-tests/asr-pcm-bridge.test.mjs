// Mock Web Audio and VM worklet contract tests, NOT real microphone/browser QA.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { startAsrPcmBridge } from '../../apps/client/web/prosody/asr-pcm-bridge.js';
const tick = () => new Promise(resolve => setImmediate(resolve));
function deferred() { let resolve, reject; const promise = new Promise((a,b) => { resolve = a; reject = b; }); return {promise,resolve,reject}; }
function fixture({ loading = Promise.resolve(), resume = Promise.resolve() } = {}) {
  const previous = { AudioContext: globalThis.AudioContext, AudioWorkletNode: globalThis.AudioWorkletNode };
  const contexts = [], nodes = [], errors = [], chunks = [];
  const track = new EventTarget(); track.readyState = 'live'; track.stops = 0; track.stop = () => track.stops++;
  const stream = { getAudioTracks: () => [track] };
  class Node {
    constructor() { this.connections = []; this.disconnects = 0; }
    connect(other) { this.connections.push(other); }
    disconnect() { this.disconnects++; }
  }
  class Context {
    constructor() {
      this.sampleRate = 48000; this.state = 'suspended'; this.destination = {};
      this.audioWorklet = { addModule: url => { this.module = url; return loading; } };
      this.closes = 0; contexts.push(this);
    }
    createMediaStreamSource(value) { assert.equal(value, stream); this.source = new Node(); return this.source; }
    createGain() { this.mute = new Node(); this.mute.gain = {value:1}; return this.mute; }
    async resume() { await resume; this.state = 'running'; }
    async close() { this.closes++; this.state = 'closed'; }
  }
  class Worklet extends Node {
    constructor(context, name, options) {
      super(); this.options = options; this.name = name; this.messages = []; this.portClosed = false;
      this.port = { postMessage: message => this.messages.push(message), close: () => { this.portClosed = true; } };
      nodes.push(this);
    }
    send(message) { this.port.onmessage?.({ data: message }); }
    chunk(sequence = 1) {
      return {type:'pcm', samples:new Float32Array(4800).fill(.25), sampleRate:48000,
        sequence, startFrame:(sequence-1)*4800};
    }
  }
  globalThis.AudioContext = Context; globalThis.AudioWorkletNode = Worklet;
  return { contexts, nodes, track, stream, errors, chunks,
    start: options => startAsrPcmBridge({ stream, onChunk:chunk=>chunks.push(chunk), onError:error=>errors.push(error), ...options }),
    restore() { for (const [key,value] of Object.entries(previous)) {
      if (value === undefined) delete globalThis[key]; else globalThis[key] = value;
    } },
  };
}

test('bridge loads only bundled worklet, uses actual rate and never owns shared tracks', async () => {
  const f = fixture(); let bridge;
  try {
    bridge = await f.start(); const context = f.contexts[0], node = f.nodes[0];
    assert.equal(context.module.pathname.endsWith('/asr-pcm-worklet.js'), true);
    assert.equal(bridge.sampleRate, 48000); assert.equal(context.mute.gain.value, 0);
    node.send(node.chunk()); await tick();
    assert.equal(f.chunks.length, 1); assert.equal(f.chunks[0].startFrame, 0);
    assert.deepEqual(node.messages, [{type:'ack',sequence:1}]);
    await bridge.stop(); await bridge.stop();
    assert.equal(context.closes, 1); assert.equal(context.source.disconnects, 1);
    assert.equal(node.portClosed, true); assert.equal(f.track.stops, 0);
    node.send(node.chunk(2)); assert.equal(f.chunks.length, 1);
  } finally { await bridge?.stop(); f.restore(); }
});

test('consumer promises serialize delivery and delay acknowledgments', async () => {
  const f=fixture(), held=deferred(); let bridge;
  try {
    bridge=await f.start({onChunk:chunk=>{f.chunks.push(chunk);return chunk.sequence===1?held.promise:undefined;}});
    const node=f.nodes[0];node.send(node.chunk(1));node.send(node.chunk(2));
    assert.equal(f.chunks.length,1);assert.equal(node.messages.length,0);
    held.resolve();await tick();
    assert.deepEqual(f.chunks.map(c=>c.sequence),[1,2]);
    assert.deepEqual(node.messages.map(m=>m.sequence),[1,2]);
  } finally { await bridge?.stop();f.restore(); }
});

test('consumer error is explicit and releases resources exactly once', async () => {
  const f=fixture();let bridge;
  try {
    bridge=await f.start({onChunk:()=>{throw new Error('ASR overload');}});
    f.nodes[0].send(f.nodes[0].chunk());await tick();
    assert.match(f.errors[0].message,/ASR overload/);assert.equal(f.contexts[0].closes,1);
    assert.equal(f.track.stops,0);assert.equal(f.nodes[0].messages.some(x=>x.type==='ack'),false);
  } finally { await bridge?.stop();f.restore(); }
});

test('gaps, wrong rates and malformed samples fail instead of corrupting time', async () => {
  for(const change of [m=>({...m,sequence:2}),m=>({...m,startFrame:1}),m=>({...m,sampleRate:16000}),m=>({...m,samples:new Float32Array([NaN])})]) {
    const f=fixture();let bridge;
    try {bridge=await f.start();f.nodes[0].send(change(f.nodes[0].chunk()));
      assert.equal(f.chunks.length,0);assert.equal(f.errors.length,1);assert.equal(f.contexts[0].closes,1);
    } finally {await bridge?.stop();f.restore();}
  }
});

test('abort during module load rejects promptly; late completion cannot revive capture', async () => {
  const loading=deferred(),f=fixture({loading:loading.promise}),controller=new AbortController();
  try {
    const start=f.start({signal:controller.signal});controller.abort();
    await assert.rejects(start,{name:'AbortError'});
    loading.resolve();await tick();
    assert.equal(f.nodes.length,0);assert.equal(f.contexts[0].closes,1);assert.equal(f.track.stops,0);
  } finally {f.restore();}
});

test('stop during consumer wait ignores late resolution without acknowledging lost audio', async () => {
  const f=fixture(),held=deferred();let bridge;
  try {
    bridge=await f.start({onChunk:()=>held.promise});const node=f.nodes[0];node.send(node.chunk());
    await bridge.stop();held.resolve();await tick();
    assert.deepEqual(node.messages,[{type:'stop'}]);assert.equal(f.errors.length,0);
  } finally {await bridge?.stop();f.restore();}
});

test('a track ended while its module loads cannot start a silent capture', async () => {
  const loading=deferred(),f=fixture({loading:loading.promise});
  try {
    const start=f.start();f.track.readyState='ended';loading.resolve();
    await assert.rejects(start,/ended during startup/);
    assert.equal(f.nodes.length,0);assert.equal(f.contexts[0].closes,1);assert.equal(f.track.stops,0);
  } finally {f.restore();}
});

test('track ending or context interruption reports one failure without stopping shared track', async () => {
  for(const mode of ['track','context','processor']) {
    const f=fixture();let bridge;
    try {bridge=await f.start();
      if(mode==='track') f.track.dispatchEvent(new Event('ended'));
      if(mode==='context'){f.contexts[0].state='suspended';f.contexts[0].onstatechange();}
      if(mode==='processor')f.nodes[0].onprocessorerror();
      assert.equal(f.errors.length,1);assert.equal(f.track.stops,0);assert.equal(f.contexts[0].closes,1);
    } finally{await bridge?.stop();f.restore();}
  }
});

function processor() {
  let Type; const sent=[];
  const scope=vm.createContext({sampleRate:8000,Float32Array,Set,Number,Error,
    AudioWorkletProcessor:class{constructor(){this.port={postMessage:message=>sent.push(message)};}},
    registerProcessor(name,value){assert.equal(name,'voicemate-asr-pcm');Type=value;}});
  vm.runInContext(fs.readFileSync(new URL('../../apps/client/web/prosody/asr-pcm-worklet.js',import.meta.url),'utf8'),scope);
  return {p:new Type({processorOptions:{chunkFrames:80,maxInFlight:2}}),sent};
}
test('actual worklet code mixes mono, preserves sequence/frame counts and silences output',()=>{
  const {p,sent}=processor(),output=new Float32Array(80).fill(1);
  assert.equal(p.process([[new Float32Array(80).fill(.2),new Float32Array(80).fill(.6)]],[[output]]),true);
  assert.equal(sent[0].sequence,1);assert.equal(sent[0].startFrame,0);assert.equal(sent[0].sampleRate,8000);
  assert.ok(Math.abs(sent[0].samples[0]-.4)<1e-6);assert.equal(output.every(x=>x===0),true);
  p.port.onmessage({data:{type:'ack',sequence:1}});
  p.process([[new Float32Array(80)]],[[output]]);
  assert.equal(sent[1].sequence,2);assert.equal(sent[1].startFrame,80);
});
test('actual worklet bounds unacknowledged chunks and fails explicitly on overflow',()=>{
  const {p,sent}=processor();
  for(let i=0;i<2;i++)assert.equal(p.process([[new Float32Array(80)]],[[]]),true);
  assert.equal(p.process([[new Float32Array(80)]],[[]]),false);
  assert.equal(sent.filter(x=>x.type==='pcm').length,2);assert.match(sent.at(-1).reason,/too slow/);
  assert.equal(p.process([[new Float32Array(80)]],[[]]),false);assert.equal(sent.length,3);
});
test('actual worklet fails on nonfinite samples, interruption and invalid acknowledgment',()=>{
  for(const mode of ['nan','missing','ack']){
    const {p,sent}=processor();
    if(mode==='nan')p.process([[new Float32Array(80).fill(NaN)]],[[]]);
    if(mode==='missing'){p.process([[new Float32Array(10)]],[[]]);p.process([[]],[[]]);}
    if(mode==='ack')p.port.onmessage({data:{type:'ack',sequence:99}});
    assert.equal(sent.at(-1).type,'error');assert.equal(p.stopped,true);
  }
});
