import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,access} from 'node:fs/promises';
const root=new URL('../../apps/client/web/prosody/',import.meta.url);
test('ASR preparation links to accessible local notices and preserves uncertainty',async()=>{
  const html=await readFile(new URL('index.html',root),'utf8');
  const controls=html.slice(html.indexOf('id="asr-controls"'),html.indexOf('id="asr-context"'));
  assert.match(controls,/<a href="\.\/asr-notices\.html" target="_blank" rel="noopener">음성 인식 모델·라이선스 고지 \(새 창\)<\/a>/);
  assert.match(controls,/변환 모델 재배포 권리는 확인 중/);
  const notices=await readFile(new URL('asr-notices.html',root),'utf8');
  assert.match(notices,/<html lang="ko">/);assert.match(notices,/<main>/);
  assert.match(notices,/변환 모델 재배포 권리는 확인 중/);
  assert.match(notices,/https:\/\/github.com\/k2-fsa\/icefall\/pull\/1655\/files/);
  assert.match(notices,/현재 배포 파일의 독립 재현/);
  assert.match(notices,/ONNXRUNTIME-ThirdPartyNotices\.txt/);
  assert.match(notices,/MODEL-ORIGINAL-CARD\.md/);assert.match(notices,/MODEL-CONVERSION-CARD\.md/);
  for(const [,href] of notices.matchAll(/href="(\.\/[^"#]+)"/g))await access(new URL(href,root));
});
