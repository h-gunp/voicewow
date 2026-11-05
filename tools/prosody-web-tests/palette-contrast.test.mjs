import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const rgb = hex => hex.match(/[a-f\d]{2}/gi).map(n => parseInt(n, 16));
const composite = (fg, alpha, bg) => fg.map((v, i) => v * alpha + bg[i] * (1 - alpha));
const luminance = color => color.map(v => { v /= 255; return v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4; }).reduce((sum, v, i) => sum + v * [.2126, .7152, .0722][i], 0);
const contrast = (a, b) => { const x = luminance(a), y = luminance(b); return (Math.max(x, y) + .05) / (Math.min(x, y) + .05); };
const css = readFileSync(new URL('../../apps/client/web/prosody/styles.css', import.meta.url), 'utf8');
const dart = readFileSync(new URL('../../apps/client/lib/app_theme.dart', import.meta.url), 'utf8');
test('glass fills retain legible blue and slate text over dark backgrounds', () => {
  assert.match(css, /background:rgba\(255,255,255,\.96\)/);
  const match = dart.match(/highContrast \? Colors.white : const Color\(0x([a-f\d]{8})\)/i);
  assert.ok(match);
  const fills = [[[255,255,255], .96], [rgb(match[1].slice(2)), parseInt(match[1].slice(0, 2), 16) / 255]];
  for (const [fill, alpha] of fills) for (const backdrop of ['000000', 'ffffff', '172b4d', '2f62d6']) for (const text of ['172b4d','52647b','2f62d6']) {
    const ratio = contrast(rgb(text), composite(fill, alpha, rgb(backdrop)));
    assert.ok(ratio >= 4.5, `${text} contrast ${ratio}`);
  }
});
test('graph lines and gauge edge remain distinguishable', () => {
  for (const background of ['ffffff', 'f0f5fc', 'eaf1fe']) {
    for (const color of ['2f62d6','b74415']) assert.ok(contrast(rgb(color), rgb(background)) >= 3);
  }
  const gauge = readFileSync(new URL('../../apps/client/lib/widgets/volume_gauge.dart', import.meta.url), 'utf8');
  assert.match(gauge, /top: BorderSide\(color: Color\(0xff0a1530\), width: 3\)/);
  for (const adjacent of ['2f62d6','82b2ff','e4ecf8','f9fbff']) assert.ok(contrast(rgb('0a1530'), rgb(adjacent)) >= 3);
});
test('live cursor and reference-end labels have readable contrast', () => {
  const charts = readFileSync(new URL('../../apps/client/web/prosody/charts.js', import.meta.url), 'utf8');
  const flutter = readFileSync(new URL('../../apps/client/lib/features/prosody/widgets/prosody_chart.dart', import.meta.url), 'utf8');
  assert.match(charts, /latestMeasured \? COLORS.voice : '#52647b'/);
  assert.match(charts, /ctx.fillStyle = '#52647b';\s*if \(right - endX/);
  assert.match(flutter, /current \? _voice : const Color\(0xff52647b\)/);
  for (const background of ['ffffff','f0f5fc','f8fafc']) assert.ok(contrast(rgb('52647b'), rgb(background)) >= 4.5);
});
