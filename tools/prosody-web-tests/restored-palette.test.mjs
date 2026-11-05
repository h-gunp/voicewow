import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

test('web compares a blue guide with an orange voice while native retains its palette', () => {
  const charts = readFileSync(new URL('../../apps/client/web/prosody/charts.js', import.meta.url), 'utf8');
  const css = readFileSync(new URL('../../apps/client/web/prosody/styles.css', import.meta.url), 'utf8');
  const dart = readFileSync(new URL('../../apps/client/lib/features/prosody/widgets/prosody_chart.dart', import.meta.url), 'utf8');
  assert.match(charts, /guide: '#2f62d6', voice: '#b74415'/);
  assert.match(css, /--coral:#b74415/);
  assert.match(dart, /_guide = Color\(0xff2f62d6\)/);
  assert.match(dart, /_voice = Color\(0xff34455e\)/);
});
