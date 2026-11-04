import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile, access} from 'node:fs/promises';
const root = new URL('../../apps/client/',import.meta.url);

test('embedded guide exposes model conditions near generation and uses a local font', async () => {
  const html = await readFile(new URL('web/prosody/index.html',root),'utf8');
  const css = await readFile(new URL('web/prosody/styles.css',root),'utf8');
  const panel = html.slice(html.indexOf('id="guide-batch-panel"'), html.indexOf('id="sentence-current-card"'));
  assert.match(panel, /href="\.\/vendor\/supertonic\/LICENSE-model\.txt"/);
  assert.match(panel, /이용 제한/);
  assert.match(css, /@font-face\s*\{[^}]*PretendardVariable\.ttf/s);
  await access(new URL('assets/fonts/PretendardVariable.ttf',root));
  await access(new URL('assets/fonts/OFL.txt',root));
  await access(new URL('web/prosody/vendor/supertonic/LICENSE-model.txt',root));
});
