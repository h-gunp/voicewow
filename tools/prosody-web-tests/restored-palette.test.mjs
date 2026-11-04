import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

test('guide and voice graphs use the previous blue and slate palette', () => {
  const charts = readFileSync(new URL('../../apps/client/web/prosody/charts.js', import.meta.url), 'utf8');
  const dart = readFileSync(new URL('../../apps/client/lib/features/prosody/widgets/prosody_chart.dart', import.meta.url), 'utf8');
  assert.match(charts, /guide: '#2f62d6', voice: '#34455e'/);
  assert.match(dart, /_guide = Color\(0xff2f62d6\)/);
  assert.match(dart, /_voice = Color\(0xff34455e\)/);
});
