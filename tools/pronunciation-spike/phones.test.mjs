import test from 'node:test';
import { ipaToPhones } from '../../apps/client/web/pronunciation/ipa-phones.mjs';
import assert from 'node:assert/strict';
import { prepareSamples, decodePhones, phonesToHangul } from './phones.mjs';

test('model input preserves raw samples, level, silence context and weak consonants', () => {
  const input = Float32Array.from({ length: 16000 }, (_, i) => Math.sin(i / 10) * .1 + .2);
  const original = input.slice();
  assert.strictEqual(prepareSamples(input, 16000), input);
  assert.deepEqual(input, original);
  const padded = new Float32Array(40000);
  padded.set(input, 16001);
  padded[16000] = .00001;
  assert.deepEqual(prepareSamples(padded, 16000), padded);
  const quiet = Float32Array.from(padded, v => v * .15);
  assert.deepEqual(prepareSamples(quiet, 16000), quiet);
  for (const bad of [new Float32Array(3200), new Float32Array(3200).fill(.3), new Float32Array(3199), new Float32Array(320001), new Float32Array(3200).fill(NaN), new Float32Array(3200).fill(2)]) {
    assert.throws(() => prepareSamples(bad, 16000));
  }
  assert.throws(() => prepareSamples(input, 24000));
  assert.throws(() => prepareSamples([.1, .2], 16000));
});

function logitsFor(ids, classes = 55) {
  const logits = new Float32Array(ids.length * classes).fill(-10);
  ids.forEach((id, frame) => logits[frame * classes + id] = 10);
  return logits;
}
const vocab = { '[PAD]': 0, 'ɡ': 1, 'k*': 2, a: 5, ' ': 51, '[UNK]': 52, '<s>': 53, '</s>': 54 };

test('CTC collapses adjacent repeats but preserves blank-separated repeats and consonant IDs 1/2', () => {
  const decoded = decodePhones(logitsFor([0, 1, 1, 0, 1, 51, 2, 5, 5, 0]), [1, 10, 55], vocab);
  assert.deepEqual(decoded, [
    { phone: 'ɡ', startFrame: 1, endFrame: 3 },
    { phone: 'ɡ', startFrame: 4, endFrame: 5 },
    { phone: 'k*', startFrame: 6, endFrame: 7 },
    { phone: 'a', startFrame: 7, endFrame: 9 },
  ]);
});

test('unknown and special tokens stay visibly unknown; delimiter carries no word boundary', () => {
  const decoded = decodePhones(logitsFor([5, 51, 5, 52, 53, 54]), [1, 6, 55], vocab);
  assert.deepEqual(decoded.map(item => item.phone), ['a', 'a', '[UNK]', '<s>', '</s>']);
  assert.equal(phonesToHangul(ipaToPhones(decoded)).text, '아아□□□');
  assert.equal(phonesToHangul(ipaToPhones(decoded)).uncertain, true);
});

test('malformed output cannot become a transcript', () => {
  assert.throws(() => decodePhones(logitsFor([0]), [2, 1, 55], vocab));
  assert.throws(() => decodePhones(logitsFor([0]), [1, 2, 55], vocab));
  assert.throws(() => decodePhones(new Float32Array(55).fill(NaN), [1, 1, 55], vocab));
  assert.throws(() => decodePhones(logitsFor([3]), [1, 1, 55], vocab));
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
