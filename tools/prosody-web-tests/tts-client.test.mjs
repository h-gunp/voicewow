import test from 'node:test';
import assert from 'node:assert/strict';

let sequence = 0;
async function fixture() {
  const original = { Worker: globalThis.Worker, isSecureContext: globalThis.isSecureContext };
  const workers = [];
  class MockWorker {
    constructor(url, options) { this.url = url; this.options = options; this.messages = []; this.terminated = false; workers.push(this); }
    postMessage(message) { this.messages.push(message); }
    terminate() { this.terminated = true; }
    send(message) { this.onmessage?.({ data: message }); }
    complete(id = this.messages.at(-1).id) { this.send({ type: 'complete', id, samples: new Float32Array(1600).fill(0.1), sampleRate: 16000, source: 'test example' }); }
  }
  globalThis.Worker = MockWorker;
  globalThis.isSecureContext = true;
  const { createTtsClient } = await import(`../../apps/client/web/prosody/tts-client.js?test=${++sequence}`);
  const client = createTtsClient();
  return { client, createTtsClient, workers, restore() {
    client.cancelGuide();
    for (const [key, value] of Object.entries(original)) {
      if (value === undefined) delete globalThis[key]; else globalThis[key] = value;
    }
  } };
}

test('TTS is lazy, returns real samples and reuses an initialized worker', async () => {
  const { client, workers, restore } = await fixture();
  try {
    assert.equal(workers.length, 0);
    const progress = [];
    const first = client.generateGuide('안녕하세요.', { onProgress: value => progress.push(value) });
    const worker = workers[0], id = worker.messages[0].id;
    assert.equal(worker.options.type, 'module');
    assert.equal(worker.messages[0].text, '안녕하세요.');
    worker.send({ type: 'progress', id, message: '준비 중', phase: 'loading', loaded: 10, total: 100 });
    assert.equal(progress[0].loaded, 10);
    worker.complete();
    const result = await first;
    assert.ok(result.samples instanceof Float32Array);
    assert.equal(result.source, 'test example');
    const second = client.generateGuide('다른 문장입니다.');
    assert.equal(workers.length, 1);
    assert.equal(worker.messages[1].text, '다른 문장입니다.');
    worker.complete(); await second;
  } finally { restore(); }
});

test('separate sessions own their worker and old cleanup cannot cancel the new session', async () => {
  const { client, createTtsClient, workers, restore } = await fixture();
  const next = createTtsClient();
  try {
    const oldRequest = client.generateGuide('기존 문장.');
    const rejected = assert.rejects(oldRequest, error => error.name === 'AbortError');
    const newRequest = next.generateGuide('새 문장.');
    assert.equal(workers.length, 2);
    client.cancelGuide();
    await rejected;
    assert.equal(workers[0].terminated, true);
    assert.equal(workers[1].terminated, false);
    workers[0].complete();
    client.cancelGuide();
    assert.equal(workers[1].terminated, false);
    workers[1].complete();
    assert.equal((await newRequest).sampleRate, 16000);
  } finally { next.cancelGuide(); restore(); }
});

test('cancel stops worker work, rejects pending request and ignores a late result', async () => {
  const { client, workers, restore } = await fixture();
  try {
    const first = client.generateGuide('첫 번째.');
    const rejection = assert.rejects(first, error => error.name === 'AbortError');
    const previous = workers[0];
    client.cancelGuide();
    assert.equal(previous.terminated, true);
    await rejection;
    const second = client.generateGuide('두 번째.');
    assert.equal(workers.length, 2);
    previous.complete(); // Cannot settle the newer request.
    workers[1].complete();
    assert.equal((await second).sampleRate, 16000);
  } finally { restore(); }
});

test('a newer generation cancels its predecessor instead of racing results', async () => {
  const { client, workers, restore } = await fixture();
  try {
    const first = client.generateGuide('앞 문장.');
    const rejection = assert.rejects(first, error => error.name === 'AbortError');
    const second = client.generateGuide('뒤 문장.');
    await rejection;
    assert.equal(workers[0].terminated, true);
    workers[1].complete(); await second;
  } finally { restore(); }
});

test('download/inference errors can be retried with a fresh worker', async () => {
  const { client, workers, restore } = await fixture();
  try {
    const first = client.generateGuide('테스트.');
    workers[0].send({ type: 'error', id: workers[0].messages[0].id, message: '모델을 내려받지 못했어요.' });
    await assert.rejects(first, /모델을 내려받지/);
    assert.equal(workers[0].terminated, true);
    const second = client.generateGuide('테스트.');
    workers[1].complete(); await second;
  } finally { restore(); }
});

test('invalid, missing or excessive audio cannot become a guide', async () => {
  const { client, workers, restore } = await fixture();
  try {
    for (const samples of [new Float32Array(), new Float32Array([NaN]), new Float32Array(16000 * 21)]) {
      const request = client.generateGuide('확인.');
      const worker = workers.at(-1);
      worker.send({ type: 'complete', id: worker.messages[0].id, samples, sampleRate: 16000 });
      await assert.rejects(request, /가이드 음성을 확인하지/);
      assert.equal(worker.terminated, true);
    }
  } finally { restore(); }
});

test('unsupported browsers and invalid scripts fail before starting a download', async () => {
  const { client, workers, restore } = await fixture();
  try {
    await assert.rejects(client.generateGuide('  '), /문장을 먼저/);
    await assert.rejects(client.generateGuide('가'.repeat(101)), /100자/);
    assert.equal(workers.length, 0);
    globalThis.Worker = undefined;
    await assert.rejects(client.generateGuide('테스트.'), /이 브라우저에서는/);
    assert.equal(workers.length, 0);
  } finally { restore(); }
});
