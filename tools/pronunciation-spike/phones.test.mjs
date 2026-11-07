import test from 'node:test';
import assert from 'node:assert/strict';
import { prepareSamples, decodePhones, phonesToHangul } from './phones.mjs';

test('normalization preserves input, rejects silence/non-finite/unsupported rates and bounds duration', () => {
  const input = Float32Array.from({ length: 16000 }, (_, i) => Math.sin(i / 10) * .1 + .2);
  const original = input.slice();
  const output = prepareSamples(input, 16000);
  assert.deepEqual(input, original);
  assert.ok(Math.abs(output.reduce((a, b) => a + b) / output.length) < 1e-5);
  assert.ok(Math.abs(output.reduce((a, b) => a + b * b, 0) / output.length - 1) < .001);
  for (const bad of [new Float32Array(3200), new Float32Array(3200).fill(.3), new Float32Array(3199), new Float32Array(320001), new Float32Array(3200).fill(NaN)]) {
    assert.throws(() => prepareSamples(bad, 16000));
  }
  assert.throws(() => prepareSamples(input, 24000));
  assert.throws(() => prepareSamples([.1, .2], 16000));
});

function logitsFor(ids, classes = 45) {
  const logits = new Float32Array(ids.length * classes).fill(-10);
  ids.forEach((id, frame) => logits[frame * classes + id] = 10);
  return logits;
}
const vocab = { A: 0, B: 1, BB: 2, '|': 40, '[UNK]': 41, '[PAD]': 42, '<s>': 43, '</s>': 44 };

test('CTC collapses adjacent repeats but preserves blank-separated repeats and consonant IDs 1/2', () => {
  const decoded = decodePhones(logitsFor([42, 1, 1, 42, 1, 40, 2, 0, 0, 42]), [1, 10, 45], vocab);
  assert.deepEqual(decoded, [
    { phone: 'B', startFrame: 1, endFrame: 3 },
    { phone: 'B', startFrame: 4, endFrame: 5 },
    { phone: 'BB', startFrame: 6, endFrame: 7 },
    { phone: 'A', startFrame: 7, endFrame: 9 },
  ]);
});

test('unknown and special tokens stay visibly unknown; delimiter carries no word boundary', () => {
  const decoded = decodePhones(logitsFor([0, 40, 0, 41, 43, 44]), [1, 6, 45], vocab);
  assert.deepEqual(decoded.map(item => item.phone), ['A', 'A', '[UNK]', '<s>', '</s>']);
  assert.equal(phonesToHangul(decoded).text, '아아□□□');
  assert.equal(phonesToHangul(decoded).uncertain, true);
});

test('malformed output cannot become a transcript', () => {
  assert.throws(() => decodePhones(logitsFor([0]), [2, 1, 45], vocab));
  assert.throws(() => decodePhones(logitsFor([0]), [1, 2, 45], vocab));
  assert.throws(() => decodePhones(new Float32Array(45).fill(NaN), [1, 1, 45], vocab));
  assert.throws(() => decodePhones(logitsFor([3]), [1, 1, 45], vocab));
});

const display = sequence => phonesToHangul(sequence.split(' ').map((phone, i) => ({ phone, startFrame: i, endFrame: i + 1 })));
test('plain, tense, aspirated and explicit coda phones remain distinct', () => {
  assert.equal(display('B A p M A D I t DD E M EO G EO DD EO').text, '밥마딛떼머거떠');
  assert.equal(display('GG E DD E SS EO DD EO').text, '께떼써떠');
  assert.equal(display('Kh A Th A Ph A CHh A').text, '카타파차');
  assert.equal(display('A N N iEO NG').text, '안녕');
});

test('merged vowels and ambiguous syllable boundaries are flagged, never recovered from a prompt', () => {
  const merged = display('GG E');
  assert.equal(merged.uncertain, true);
  assert.ok(merged.segments[0].notes.some(note => note.includes('ㅐ/ㅔ')));
  assert.equal(display('A N A').uncertain, true);
  assert.equal(display('B').text, 'ㅂ');
  assert.equal(display('B').uncertain, true);
  assert.equal(display('uEO').text, '□');
  assert.equal(display('uEO').uncertain, true);
});
