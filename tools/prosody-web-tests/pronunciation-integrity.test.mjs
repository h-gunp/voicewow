import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { sha256 } from '../../apps/client/web/pronunciation/sha256.mjs';

test('bounded SHA-256 matches standard vectors without whole-buffer WebCrypto copies', async t => {
  t.mock.method(crypto.subtle, 'digest', () => { throw new Error('Whole-buffer digest is forbidden'); });
  for (const bytes of [new Uint8Array(), new TextEncoder().encode('abc'), new Uint8Array(1000000).fill(97),
    Uint8Array.from({ length: 1048583 }, (_, index) => index % 251)]) {
    const expected = createHash('sha256').update(bytes).digest('hex');
    assert.equal(await sha256(bytes), expected);
    assert.equal(await sha256(bytes.buffer), expected);
  }
  const padded = Uint8Array.of(255, 1, 2, 3, 255);
  assert.equal(await sha256(padded.subarray(1, 4)), createHash('sha256').update(Uint8Array.of(1,2,3)).digest('hex'));
});
