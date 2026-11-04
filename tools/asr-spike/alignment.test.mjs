import test from 'node:test';
import assert from 'node:assert/strict';
import { alignFinal } from './alignment.mjs';
const source = '  오늘은 날씨가 좋습니다. 내일은 도서관에 갑니다.  ';
test('final recognized range keeps original offsets and context', () => {
  const r = alignFinal(source, '오늘은날씨가좋습니다', { final: true });
  assert.equal(source.slice(r.range.start, r.range.end), '오늘은 날씨가 좋습니다');
  assert.equal(r.before, '  '); assert.match(r.after, /내일은/);
});
test('partial revisions never mark a confirmed position', () => {
  assert.deepEqual(alignFinal(source, '오늘은 날씨가 좋습니다'), { status: 'partial', range: null });
});
test('repeated sentence is ambiguous, never first indexOf', () => {
  assert.equal(alignFinal('오늘은 날씨가 좋습니다. 오늘은 날씨가 좋습니다.', '오늘은 날씨가 좋습니다', { final:true }).status, 'ambiguous');
});
test('explicit selection resolves repetition without inventing a position', () => {
  const s = '오늘은 날씨가 좋습니다. 오늘은 날씨가 좋습니다.';
  const r = alignFinal(s, '오늘은 날씨가 좋습니다', { final:true, scope:[14,s.length] });
  assert.ok(r.range.start >= 14);
});
test('omission confirms only later matching phrase, not skipped text', () => {
  const r = alignFinal(source, '내일은 도서관에 갑니다', { final:true });
  assert.equal(r.text, '내일은 도서관에 갑니다');
});
test('rereading can return to earlier range', () => {
  const later = alignFinal(source, '내일은 도서관에 갑니다', { final:true });
  const earlier = alignFinal(source, '오늘은 날씨가 좋습니다', { final:true });
  assert.ok(earlier.range.start < later.range.start);
});
test('unknown and short inputs hold position', () => {
  assert.equal(alignFinal(source, '전혀 다른 이야기를 합니다', {final:true}).status, 'uncertain');
  assert.equal(alignFinal(source, '네', {final:true}).status, 'insufficient');
});
test('decomposed Hangul and emoji preserve raw source offsets', () => {
  const s = '😀 ' + '오늘은 날씨가 좋습니다'.normalize('NFD') + '!';
  const r = alignFinal(s, '오늘은 날씨가 좋습니다', {final:true});
  assert.equal(r.range.start, 3); assert.equal(r.range.end, s.length - 1);
  assert.equal(r.text.normalize('NFC'), '오늘은 날씨가 좋습니다');
});
test('ASR substitution at the end does not fabricate a match', () => {
  assert.equal(alignFinal(source, '오늘은 날씨가 흐립니다', {final:true}).status, 'uncertain');
});
test('invalid bounds and excessive inputs fail explicitly', () => {
  assert.throws(() => alignFinal(source, 'hello', {scope:[-1,10]}));
  assert.throws(() => alignFinal('가'.repeat(8001), 'hello'));
});
