import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

class Port {
  messages = [];
  waiting = [];
  postMessage(message) {
    this.messages.push(message);
    for (const waiter of this.waiting) if (waiter.type === message.type) waiter.resolve(message);
  }
  next(type) {
    const existing = this.messages.find(message => message.type === type);
    return existing ? Promise.resolve(existing) : new Promise(resolve => this.waiting.push({type,resolve}));
  }
}
globalThis.sampleRate = 48000;
globalThis.AudioWorkletProcessor = class { constructor() { this.port = new Port(); } };
let Processor;
globalThis.registerProcessor = (name, constructor) => {
  assert.equal(name, 'voicemate-noise-meter');
  Processor = constructor;
};
await import('../../apps/client/web/audio/noise-reduction-worklet.mjs');
const wasmBinary = await readFile(new URL('../../apps/client/web/audio/vendor/rnnoise/rnnoise.wasm', import.meta.url));
const vadBinary = await readFile(new URL('../../apps/client/web/audio/vendor/libfvad/libfvad.wasm', import.meta.url));
const create = () => new Processor({processorOptions:{wasmBinary}});

test('worklet sends aligned raw PCM only while speaker capture is explicitly enabled', {timeout:3000}, async()=>{
 const processor=new Processor({processorOptions:{wasmBinary,vadBinary}});await processor.port.next('ready');
 for(let i=0;i<110;i++)processor.process([[new Float32Array(480).fill(.02)]]);
 assert.equal(processor.port.messages.some(x=>x.type==='speaker_window'),false);
 processor.port.onmessage({data:{type:'speaker_capture',enabled:true,generation:1}});
 for(let i=0;i<110;i++)processor.process([[new Float32Array(480).fill(.03)]]);
 const windows=processor.port.messages.filter(x=>x.type==='speaker_window');assert.equal(windows.length,1);assert.equal(windows[0].generation,1);assert.equal(windows[0].pcm.length,48000);assert.equal(windows[0].sampleEnd-windows[0].sampleStart,48000);
 processor.port.onmessage({data:{type:'speaker_capture',enabled:false,generation:2}});
 for(let i=0;i<110;i++)processor.process([[new Float32Array(480).fill(.04)]]);
 assert.equal(processor.port.messages.filter(x=>x.type==='speaker_window').length,1);processor.port.onmessage({data:{type:'dispose'}});
});

test('real RNNoise and VAD worklet emits aligned raw analysis without samples', {timeout:2000}, async () => {
  const processor = new Processor({processorOptions:{wasmBinary,vadBinary}});
  const ready = await processor.port.next('ready');
  assert.equal(ready.vadStatus, 'ready');
  globalThis.currentFrame = 96000;
  processor.process([[new Float32Array(480).fill(.25)]]);
  processor.process([[new Float32Array(480).fill(.5)]]);
  const frame = processor.port.messages.find(m=>m.type === 'analysis');
  assert.equal(frame.seq, 0);
  assert.equal(frame.sampleStart, 0);
  assert.equal(frame.sampleTime, 2.01);
  assert.equal(frame.power, .0625);
  assert.ok(['speech','nonSpeech','uncertain'].includes(frame.speech));
  processor.port.onmessage({data:{type:'dispose'}});
  delete globalThis.currentFrame;
});

test('invalid VAD binary keeps RNNoise level meter running', {timeout:2000}, async () => {
  const processor = new Processor({processorOptions:{wasmBinary,vadBinary:new Uint8Array([0])}});
  const ready = await processor.port.next('ready');
  assert.equal(ready.vadStatus, 'init_failed');
  processor.process([[new Float32Array(4800)]]);
  assert.equal(processor.port.messages.filter(m=>m.type === 'level').length, 1);
  assert.equal(processor.port.messages.some(m=>m.type === 'analysis'), false);
  processor.port.onmessage({data:{type:'dispose'}});
});

test('input gap restarts the sample clock and does not mix pre-gap audio', {timeout:2000}, async () => {
  const processor = new Processor({processorOptions:{wasmBinary,vadBinary}});
  await processor.port.next('ready');
  globalThis.currentFrame=96000;
  for(let i=0;i<40;i++){processor.process([[new Float32Array(128).fill(.2)]]);globalThis.currentFrame+=128;}
  const before=processor.port.messages.length;
  for(let i=0;i<450;i++){processor.process([]);globalThis.currentFrame+=128;}
  const resumeFrame=globalThis.currentFrame;
  for(let i=0;i<40;i++){processor.process([[new Float32Array(128)]]);globalThis.currentFrame+=128;}
  const messages=processor.port.messages.slice(before);
  assert.equal(messages.filter(x=>x.type==='analysis_reset').length,1);
  const analysis=messages.find(x=>x.type==='analysis');
  assert.equal(analysis.seq,0);
  assert.ok(Math.abs(analysis.sampleTime-(resumeFrame+480)/48000)<1e-8);
  assert.equal(analysis.power,0);
  assert.equal(messages.find(x=>x.type==='level').rms,0);
  processor.port.onmessage({data:{type:'dispose'}}); delete globalThis.currentFrame;
});

test('real_engine_worklet_waits_for_ready_then_reports_100ms_without_sending_samples', {timeout:2000}, async () => {
  const processor = create();
  assert.equal(processor.process([[new Float32Array(128)]]), true);
  assert.deepEqual(processor.port.messages, []);
  await processor.port.next('ready');
  assert.equal(processor.process([]), true);
  for (let i=0; i<38; i++) assert.equal(processor.process([[new Float32Array(128)]]), true);
  const levels = processor.port.messages.filter(message => message.type === 'level');
  assert.deepEqual(levels, [{type:'level',rms:0,peak:0,dbfs:null,normalized:0,sampleCount:4800}]);
  processor.port.onmessage({data:{type:'dispose'}});
  assert.equal(processor.process([[new Float32Array(128)]]), false);
});

test('dispose_during_engine_initialization_cannot_revive_processing', {timeout:2000}, async () => {
  const processor = create();
  processor.port.onmessage({data:{type:'dispose'}});
  await new Promise(resolve => setTimeout(resolve, 50));
  assert.deepEqual(processor.port.messages, []);
  assert.equal(processor.process([[new Float32Array(4800)]]), false);
});

test('invalid_samples_end_processing_and_emit_one_error_instead_of_a_silent_meter', {timeout:2000}, async () => {
  const processor = create();
  await processor.port.next('ready');
  assert.equal(processor.process([[new Float32Array([NaN])]]), false);
  assert.equal(processor.process([[new Float32Array(4800)]]), false);
  assert.deepEqual(processor.port.messages.map(message => message.type), ['ready','error']);
  processor.port.onmessage({data:{type:'dispose'}});
});
