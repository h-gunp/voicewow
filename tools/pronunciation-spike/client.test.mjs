import test from 'node:test';
import assert from 'node:assert/strict';
import { createPhoneClient } from './client.mjs';

function fixture() {
  const original = globalThis.Worker;
  const workers = [];
  globalThis.Worker = class {
    constructor() { this.messages = []; workers.push(this); }
    postMessage(message) { this.messages.push(message); }
    terminate() { this.terminated = true; }
    send(type, extra = {}) { this.onmessage?.({ data: { type, id: this.messages.at(-1).id, ...extra } }); }
  };
  const client = createPhoneClient();
  return { client, workers, restore() { client.cancel(); if (original === undefined) delete globalThis.Worker; else globalThis.Worker = original; } };
}

test('lazy worker preparation gates recognition and keeps original PCM for local replay', async () => {
  const f = fixture();
  try {
    assert.equal(f.workers.length, 0);
    await assert.rejects(f.client.recognize(new Float32Array(16000), 16000), /준비/);
    const prepared = f.client.prepare();
    const worker = f.workers[0];
    worker.send('ready'); await prepared;
    const samples = new Float32Array(16000).fill(.1);
    const result = f.client.recognize(samples, 16000);
    assert.notEqual(worker.messages.at(-1).samples, samples);
    worker.send('result', { result: { phones: [], display: { text: '', segments: [] }, inferenceMs: 1, duration: 1 } });
    assert.equal((await result).duration, 1);
    assert.equal(f.client.ready, true);
  } finally { f.restore(); }
});

test('cancel rejects the pending request and an old worker cannot settle a new request', async () => {
  const f = fixture();
  try {
    const first = f.client.prepare();
    const rejected = assert.rejects(first, error => error.name === 'AbortError');
    const old = f.workers[0];
    f.client.cancel(); await rejected;
    assert.equal(old.terminated, true);
    const second = f.client.prepare();
    old.send('ready');
    assert.equal(f.client.ready, false);
    f.workers[1].send('ready'); await second;
    assert.equal(f.client.ready, true);
  } finally { f.restore(); }
});

test('duplicate input is rejected and a failed worker can be prepared again', async () => {
  const f = fixture();
  try {
    const first = f.client.prepare();
    await assert.rejects(f.client.prepare(), /진행 중/);
    f.workers[0].send('error', { message: '모델 파일을 찾을 수 없다.' });
    await assert.rejects(first, /모델 파일/);
    assert.equal(f.client.ready, false);
    assert.equal(f.workers[0].terminated, true);
    const second = f.client.prepare();
    f.workers[1].send('ready'); await second;
    await assert.rejects(f.client.recognize(new Float32Array(320001), 16000));
    await assert.rejects(f.client.recognize(new Float32Array(3200).fill(NaN), 16000));
  } finally { f.restore(); }
});

test('malformed results fail explicitly instead of displaying a stale result', async () => {
  const f = fixture();
  try {
    const prepared = f.client.prepare(); f.workers[0].send('ready'); await prepared;
    const result = f.client.recognize(new Float32Array(3200).fill(.1), 16000);
    f.workers[0].send('result', { result: { display: { text: '가짜' } } });
    await assert.rejects(result, /결과/);
    assert.equal(f.client.ready, false);
  } finally { f.restore(); }
});
