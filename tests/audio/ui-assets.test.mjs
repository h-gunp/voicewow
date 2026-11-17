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

test('web app metadata and install icons resolve to bundled files', async () => {
  const html = await readFile(new URL('web/index.html', root), 'utf8');
  const manifest = JSON.parse(await readFile(new URL('web/manifest.json', root), 'utf8'));
  assert.match(html, /rel="manifest" href="manifest.json"/);
  assert.match(html, /rel="apple-touch-icon" href="icons\/apple-touch-icon.png"/);
  assert.equal(manifest.name, 'VoiceMate');
  assert.equal(manifest.theme_color, '#f2f5f7');
  assert.ok(manifest.icons.some(icon => icon.purpose === 'maskable'));
  for (const path of ['favicon.png', 'icons/apple-touch-icon.png', ...manifest.icons.map(icon => icon.src)]) {
    await access(new URL(`web/${path}`, root));
  }
});
