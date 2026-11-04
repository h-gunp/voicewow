import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {locateScript,sourceRanges,ScriptTracker} from '../../apps/client/web/prosody/script-alignment.js';
const fixtures=JSON.parse(fs.readFileSync(new URL('../asr-spike/evidence/native-report.json',import.meta.url))).results;
test('all four real hypotheses retain exact supported text without marking errors',()=>{
  for(const f of fixtures) {
    const r=locateScript(f.reference,f.final.text);
    assert.ok(r.range);assert.equal(f.reference.slice(r.range.start,r.range.end),r.text);
  }
  assert.equal(locateScript(fixtures[0].reference,fixtures[0].final.text).status,'uncertain-tail');
  assert.equal(locateScript(fixtures[1].reference,fixtures[1].final.text).status,'uncertain-tail');
});
test('shared prefix with contradictory ending is explicitly uncertain, not current position',()=>{
  const r=locateScript('저는 오늘 행사에 참여하겠습니다.','저는 오늘 행사에 참여하지 않겠습니다');
  assert.equal(r.status,'uncertain-tail');assert.ok(r.trailingUnmatched>0);
  assert.ok(!r.text.includes('하겠습니다'));
});
test('repeated source is ambiguous and source ranges preserve distinct occurrences',()=>{
  const s='  오늘은 좋은 날입니다.\n오늘은 좋은 날입니다.';
  assert.equal(locateScript(s,'오늘은좋은날입니다').status,'ambiguous');
  const ranges=sourceRanges(s,['오늘은 좋은 날입니다.','오늘은 좋은 날입니다.']);
  assert.ok(ranges[1].start>ranges[0].end);
  assert.equal(locateScript(s,'오늘은좋은날입니다',{scope:ranges[1]}).range.start,ranges[1].start);
});
test('unrelated speech, noise-empty hypothesis and short interjection do not match',()=>{
  const s='오늘은 새로운 기술에 대해 발표하겠습니다.';
  for(const h of ['','네','점심에는 김치찌개를 먹었습니다']) assert.equal(locateScript(s,h).range,null);
});
test('skip and reread locate only supported ranges',()=>{
  const s='첫 번째 발표를 시작하겠습니다. 다음 단계 설명을 마치겠습니다.';
  const a=locateScript(s,'다음 단계 설명을 마치겠습니다');
  const b=locateScript(s,'첫 번째 발표를 시작하겠습니다');
  assert.ok(a.range.start>b.range.end);assert.equal(a.text,'다음 단계 설명을 마치겠습니다');
});
test('Unicode original offsets survive normalization',()=>{
  const s='😀 '+ '오늘은 좋은 날입니다'.normalize('NFD');
  const r=locateScript(s,'오늘은좋은날입니다');assert.equal(r.range.start,3);assert.equal(r.range.end,s.length);
});
test('streaming revisions clear evidence and stale observations cannot stabilize',()=>{
  const t=new ScriptTracker('오늘은 좋은 날입니다.');
  assert.equal(t.update({text:'오늘은 좋은 날입니다',sequence:1}).status,'tentative');
  assert.equal(t.update({text:'오늘은 좋은 날입니다',sequence:1}).status,'stale');
  assert.equal(t.update({text:'오늘은 좋은 날입니다',sequence:2}).status,'matched');
  assert.equal(t.update({text:'전혀 다른 이야기',sequence:3}).range,null);
  assert.equal(t.update({text:'오늘은 좋은 날입니다',sequence:4,final:'true'}).status,'tentative');
  t.reset();assert.equal(t.update({text:'오늘은 좋은 날입니다',sequence:0,final:true}).status,'matched');
});
