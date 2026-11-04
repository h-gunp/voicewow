import test from 'node:test';
import assert from 'node:assert/strict';
import { parseScript, parsePracticeScript, selectLocalKoreanVoice,
  TARGET_PRACTICE_UNIT_CHARACTERS, MAX_PRACTICE_UNIT_CHARACTERS, MAX_PRACTICE_UNITS } from '../../apps/client/web/prosody/script-utils.js';

test('script is separated by Korean sentence punctuation and line breaks', () => {
  assert.deepEqual(parseScript('안녕하세요. 잠시 말씀드릴게요!\n잘 들리시나요?\r\n감사합니다.'),
    ['안녕하세요.', '잠시 말씀드릴게요!', '잘 들리시나요?', '감사합니다.']);
  assert.deepEqual(parseScript('첫 문장입니다.둘째 문장입니다.'), ['첫 문장입니다.', '둘째 문장입니다.']);
});

test('decimals and common abbreviations are not separated into tiny sentences', () => {
  assert.deepEqual(parseScript('Dr. Kim은 3.14를 말했다. U.S. 자료도 확인했다.'),
    ['Dr. Kim은 3.14를 말했다.', 'U.S. 자료도 확인했다.']);
  assert.deepEqual(parseScript('예: e.g. apple. 다음입니다.'), ['예: e.g. apple.', '다음입니다.']);
});

test('long sentences split on words and long unspaced Korean text stays complete', () => {
  const script = '가나다라마바사'.repeat(40);
  const parts = parseScript(script);
  assert.deepEqual(parts.map(part => Array.from(part).length), [100, 100, 80]);
  assert.equal(parts.join(''), script);
  const words = '작은 목소리로 천천히 말하기 '.repeat(20).trim();
  const wordParts = parseScript(words);
  assert.ok(wordParts.every(part => Array.from(part).length <= 100));
  assert.equal(wordParts.join(' '), words);
});

test('punctuation clusters, quotes and Unicode characters are preserved', () => {
  const script = '“괜찮아요?!” 정말요...\n네！ 😀와 함께 '.repeat(5);
  const parts = parseScript(script);
  assert.equal(parts.join('').replace(/\s/gu, ''), script.replace(/\s/gu, ''));
  assert.ok(parts.every(part => Array.from(part).length <= 100));
  assert.ok(parts[0].endsWith('?!”'));
});

test('limits report errors without silently truncating content', () => {
  for (const text of ['', ' \n\t ']) assert.throws(() => parseScript(text), /먼저 입력/u);
  assert.throws(() => parseScript(null), /글로 입력/u);
  assert.throws(() => parseScript('가'.repeat(2001)), /2,000자/u);
  assert.equal(parseScript('가'.repeat(2000)).join('').length, 2000);
  assert.throws(() => parseScript('네.\n'.repeat(31)), /30개 구간/u);
  assert.equal(parseScript('네.\n'.repeat(30)).length, 30);
});

test('script playback never selects a remote or non-Korean voice', () => {
  const remote = { name: 'Remote Korean', lang: 'ko-KR', localService: false, default: true };
  const english = { name: 'Local English', lang: 'en-US', localService: true, default: true };
  const local = { name: 'Local Korean', lang: 'ko-KR', localService: true };
  const defaultLocal = { name: 'Default Korean', lang: 'ko', localService: true, default: true };
  assert.equal(selectLocalKoreanVoice([remote, english]), null);
  assert.equal(selectLocalKoreanVoice([remote, english, local]), local);
  assert.equal(selectLocalKoreanVoice([local, defaultLocal]), defaultLocal);
  assert.equal(selectLocalKoreanVoice([{ lang: 'ko-KR' }]), null);
  assert.equal(selectLocalKoreanVoice([]), null);
});

test('short practice preparation keeps sentence context and zero-based part metadata', () => {
  const text = 'Dr. Kim은 3.14를 말했다.\n  천천히   읽어 주세요! 다음 문장입니다.';
  assert.deepEqual(parsePracticeScript(text), [
    { text: 'Dr. Kim은 3.14를 말했다.', sentenceText: 'Dr. Kim은 3.14를 말했다.', sentenceIndex: 0, partIndex: 0, partCount: 1 },
    { text: '천천히 읽어 주세요!', sentenceText: '천천히 읽어 주세요!', sentenceIndex: 1, partIndex: 0, partCount: 1 },
    { text: '다음 문장입니다.', sentenceText: '다음 문장입니다.', sentenceIndex: 2, partIndex: 0, partCount: 1 },
  ]);
  assert.equal(TARGET_PRACTICE_UNIT_CHARACTERS, 50);
  assert.equal(MAX_PRACTICE_UNIT_CHARACTERS, 60);
});

test('long practice sentences prefer clauses or spaces and retain every non-whitespace character', () => {
  const clause = '오늘은 편안한 속도로 준비한 문장을 천천히 읽어 보려고 합니다,';
  const text = `${clause} 다음에는 결과를 살펴보고 연습하고 싶은 부분을 골라 다시 읽어 볼 예정입니다.\n다음입니다.`;
  const units = parsePracticeScript(text);
  assert.ok(units.length > 2);
  assert.ok(units[0].text.endsWith(','), 'use an available clause boundary before splitting a word');
  assert.ok(units.every(unit => Array.from(unit.text).length <= 60));
  assert.equal(units.map(unit => unit.text).join('').replace(/\s/gu, ''), text.replace(/\s/gu, ''));
  const firstSentence = units.filter(unit => unit.sentenceIndex === 0);
  assert.deepEqual(firstSentence.map(unit => unit.partIndex), firstSentence.map((_, index) => index));
  assert.ok(firstSentence.every(unit => unit.partCount === firstSentence.length));
  assert.ok(firstSentence.every(unit => unit.sentenceText === `${clause} 다음에는 결과를 살펴보고 연습하고 싶은 부분을 골라 다시 읽어 볼 예정입니다.`));
});

test('unspaced Unicode fallback is a lossless text split with no tiny final fragment', () => {
  for (const text of ['가'.repeat(61), '😀가나다'.repeat(70)]) {
    const units = parsePracticeScript(text);
    assert.equal(units.map(unit => unit.text).join(''), text);
    assert.ok(units.every(unit => Array.from(unit.text).length <= 60));
    assert.ok(units.every(unit => unit.sentenceText === text));
  }
  assert.ok(parsePracticeScript('가'.repeat(61)).every(unit => Array.from(unit.text).length >= 20));
});

test('manual newlines always separate practice sentences and limits never truncate', () => {
  const units = parsePracticeScript('첫 부분은 여기까지\r\n둘째 부분\u2028셋째 부분');
  assert.deepEqual(units.map(unit => unit.text), ['첫 부분은 여기까지', '둘째 부분', '셋째 부분']);
  assert.deepEqual(units.map(unit => unit.sentenceIndex), [0, 1, 2]);
  assert.equal(MAX_PRACTICE_UNITS, 60);
  assert.equal(parsePracticeScript('네.\n'.repeat(60)).length, 60);
  assert.throws(() => parsePracticeScript('네.\n'.repeat(61)), /60개 연습 조각/u);
  assert.throws(() => parsePracticeScript('가'.repeat(2001)), /2,000자/u);
  assert.equal(parsePracticeScript('가'.repeat(2000)).map(unit => unit.text).join(''), '가'.repeat(2000));
  for (const value of ['', '\n\t ']) assert.throws(() => parsePracticeScript(value), /먼저 입력/u);
  assert.throws(() => parsePracticeScript(null), /글로 입력/u);
  // The legacy API keeps its separate 100-character / 30-section contract.
  assert.deepEqual(parseScript('가'.repeat(201)).map(part => part.length), [100, 100, 1]);
  assert.throws(() => parseScript('네.\n'.repeat(31)), /30개 구간/u);
});
