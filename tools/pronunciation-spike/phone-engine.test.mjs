import test from 'node:test';
import assert from 'node:assert/strict';
import { createPhoneEngine, MODEL_ASSETS } from './phone-engine.mjs';

test('truncated model assets fail before a session is created', async () => {
  await assert.rejects(createPhoneEngine({ loadAsset: async () => new Uint8Array(1) }), /모델 파일/);
});

test('loader failure is propagated; fixed assets do not contain audio or text requests', async () => {
  const problem = new Error('offline fixture missing');
  await assert.rejects(createPhoneEngine({ loadAsset: async () => { throw problem; } }), error => error === problem);
  assert.equal(MODEL_ASSETS.find(asset => asset.path.endsWith('.onnx')).bytes, 356129122);
  for (const asset of MODEL_ASSETS) {
    assert.match(asset.sha256, /^[a-f0-9]{64}$/);
    assert.ok(!asset.path.includes('..'));
  }
});
