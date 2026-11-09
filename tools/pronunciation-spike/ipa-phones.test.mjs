import test from 'node:test';
import assert from 'node:assert/strict';
import { ipaToPhones } from '../../apps/client/web/pronunciation/ipa-phones.mjs';
import { phonesToHangul } from './phones.mjs';

const convert = text => ipaToPhones(text.split(' ').map((phone, i) => ({ phone, startFrame: i, endFrame: i + 1 })));
test('IPA observations preserve errors and tense/aspirated contrasts without a reference', () => {
  const result = convert('b a p m a d i t t* ɛ m ʌ ɡ ʌ t* ʌ');
  assert.equal(phonesToHangul(result).text, '밥마딛떼머거떠');
  assert.equal(phonesToHangul(convert('k* a t* a p* a tɕ* a s* a')).text, '까따빠짜싸');
  assert.equal(phonesToHangul(convert('kʰ a tʰ a pʰ a tɕʰ a')).text, '카타파차');
  assert.deepEqual(result.map(x => [x.startFrame, x.endFrame]), Array.from({length: 16}, (_, i) => [i, i + 1]));
});
test('voicing is an allophone; coda placement uses observed neighbors only', () => {
  assert.equal(phonesToHangul(convert('k a ɡ a t a d a p a b a')).text, '가가다다바바');
  assert.equal(phonesToHangul(convert('a k a t a p')).text, '아가답');
  assert.equal(phonesToHangul(convert('a n n jʌ ŋ')).text, '안녕');
  assert.equal(phonesToHangul(convert('wʌ n')).text, '원');
});
test('merged vowels and unknown tokens remain uncertain', () => {
  assert.equal(phonesToHangul(convert('ɛ')).uncertain, true);
  assert.equal(phonesToHangul(convert('[UNK] <s> </s> impossible')).text, '□□□□');
  assert.equal(phonesToHangul(convert('__proto__ constructor toString')).text, '□□□');
  assert.throws(() => ipaToPhones(Array(1001).fill({phone:'a'})));
});
