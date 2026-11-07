import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const rgb = hex => hex.match(/[a-f\d]{2}/gi).map(n => parseInt(n, 16));
const luminance = color => color.map(v => { v /= 255; return v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4; }).reduce((sum, v, i) => sum + v * [.2126, .7152, .0722][i], 0);
const contrast = (a, b) => { const x = luminance(a), y = luminance(b); return (Math.max(x, y) + .05) / (Math.min(x, y) + .05); };
const css = readFileSync(new URL('../../apps/client/web/prosody/styles.css', import.meta.url), 'utf8');
const dart = readFileSync(new URL('../../apps/client/lib/app_theme.dart', import.meta.url), 'utf8');
const webColor = name => {
  const match = css.match(new RegExp(`--${name}:#([a-f\\d]{6})\\b`, 'i'));
  assert.ok(match, `missing web color ${name}`);
  return match[1];
};
const nativeColor = name => {
  const match = dart.match(new RegExp(`\\b${name} = Color\\(0xff([a-f\\d]{6})\\)`, 'i'));
  assert.ok(match, `missing native color ${name}`);
  return match[1];
};
test('solid native and web surfaces retain readable text and controls', () => {
  for (const [name, value] of Object.entries({canvas:'fafaf7', ink:'252a27', muted:'626b65', accent:'315b49', wash:'edf2ec'})) {
    assert.equal(webColor(name), value);
    assert.equal(nativeColor(name), value);
  }
  assert.doesNotMatch(css, /(?:radial|linear)-gradient|backdrop-filter:\s*blur|box-shadow:\s*(?!none)[^;}\s]/);
  for (const surface of ['ffffff', webColor('canvas'), webColor('wash')]) {
    for (const text of ['ink', 'muted', 'accent']) {
      const ratio = contrast(rgb(webColor(text)), rgb(surface));
      assert.ok(ratio >= 4.5, `${text} on ${surface} contrast ${ratio}`);
    }
  }
  assert.ok(contrast(rgb('ffffff'), rgb(webColor('accent'))) >= 4.5);
});
test('graph lines and solid gauge boundaries remain distinguishable', () => {
  for (const background of ['ffffff', webColor('canvas'), webColor('wash')]) {
    for (const color of ['2f62d6','b74415']) assert.ok(contrast(rgb(color), rgb(background)) >= 3);
  }
  const gauge = readFileSync(new URL('../../apps/client/lib/widgets/volume_gauge.dart', import.meta.url), 'utf8');
  assert.match(gauge, /top: BorderSide\(color: ink, width: 3\)/);
  assert.match(gauge, /color: blue,/);
  assert.doesNotMatch(gauge, /LinearGradient/);
  assert.match(dart, /blue = accent/);
  const rail = gauge.match(/key: const Key\('gauge-rail'\)[\s\S]*?color: const Color\(0xff([a-f\d]{6})\)/i);
  assert.ok(rail);
  for (const color of ['accent','ink','red']) assert.ok(contrast(rgb(nativeColor(color)), rgb(rail[1])) >= 3, `${color} on gauge rail`);
  assert.match(gauge, /color: red,[\s\S]*?key: key/);
});
test('live cursor and reference-end labels have readable contrast', () => {
  const charts = readFileSync(new URL('../../apps/client/web/prosody/charts.js', import.meta.url), 'utf8');
  const flutter = readFileSync(new URL('../../apps/client/lib/features/prosody/widgets/prosody_chart.dart', import.meta.url), 'utf8');
  assert.match(charts, /latestMeasured \? COLORS.voice : '#52647b'/);
  assert.match(charts, /ctx.fillStyle = '#52647b';\s*if \(right - endX/);
  assert.match(flutter, /current \? _voice : const Color\(0xff52647b\)/);
  for (const background of ['ffffff','f0f5fc','f8fafc']) assert.ok(contrast(rgb('52647b'), rgb(background)) >= 4.5);
});
