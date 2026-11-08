import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

test('web compares a blue guide with an orange voice while native retains its palette', () => {
  const charts = readFileSync(new URL('../../apps/client/web/prosody/charts.js', import.meta.url), 'utf8');
  const css = readFileSync(new URL('../../apps/client/web/prosody/styles.css', import.meta.url), 'utf8');
  const dart = readFileSync(new URL('../../apps/client/lib/features/prosody/widgets/prosody_chart.dart', import.meta.url), 'utf8');
  assert.match(charts, /guide: '#2f62d6', voice: '#b74415'/);
  assert.match(css, /--blue:#2f62d6/);
  assert.match(css, /--coral:#b74415/);
  assert.match(css, /--accent:#315b49/);
  assert.match(dart, /_guide = Color\(0xff2f62d6\)/);
  assert.match(dart, /_voice = Color\(0xff34455e\)/);
});

test('web keeps compact mode rows, accessible mobile toolbar and flow layout contracts', () => {
  const html = readFileSync(new URL('../../apps/client/web/prosody/index.html', import.meta.url), 'utf8');
  const css = readFileSync(new URL('../../apps/client/web/prosody/styles.css', import.meta.url), 'utf8');
  assert.match(html, /class="practice-toolbar"/);
  assert.match(html, /class="mode-back-icon" aria-hidden="true"/);
  assert.match(html, /class="mode-back-label"/);
  assert.match(css, /grid-template-columns:48px minmax\(0,1fr\) 24px/);
  assert.match(css, /\.practice-toolbar #change-mode\s*\{[^}]*width: 44px;[^}]*min-height: 44px/);
  assert.match(css, /\.mode-back-label\s*\{[^}]*clip-path: inset\(50%\)/);
  assert.match(css, /\.embedded main.shell\{height:var\(--surface-height,100dvh\)/);
  assert.match(css, /\.embedded \.flow-deck\{flex:1;min-height:0;height:auto/);
  for (const feature of ['prefers-reduced-motion','prefers-contrast','forced-colors',':focus-visible']) assert.ok(css.includes(feature), feature);
});
