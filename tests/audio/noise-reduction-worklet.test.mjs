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
const create = () => new Processor({processorOptions:{wasmBinary}});

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
