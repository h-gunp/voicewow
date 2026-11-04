import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const rgb = hex => hex.match(/[a-f\d]{2}/gi).map(n => parseInt(n, 16));
const composite = (fg, alpha, bg) => fg.map((v, i) => v * alpha + bg[i] * (1 - alpha));
const luminance = color => color.map(v => { v /= 255; return v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4; }).reduce((sum, v, i) => sum + v * [.2126, .7152, .0722][i], 0);
const contrast = (a, b) => { const x = luminance(a), y = luminance(b); return (Math.max(x, y) + .05) / (Math.min(x, y) + .05); };
const css = readFileSync(new URL('../../apps/client/web/prosody/styles.css', import.meta.url), 'utf8');
const dart = readFileSync(new URL('../../apps/client/lib/app_theme.dart', import.meta.url), 'utf8');

test('actual glass fills retain readable core text even over black and palette extrema', () => {
  const webFill = [...css.matchAll(/background:rgba\((231,248,246),(\.\d+)\)/g)].at(-1);
  assert.ok(webFill, 'audited web control fill exists');
  const flutterFill = dart.match(/highContrast \? Colors.white : const Color\(0x([a-f\d]{8})\)/i);
  assert.ok(flutterFill, 'audited Flutter navigation fill exists');
  const fills = [[webFill[1].split(',').map(Number), Number(webFill[2])], [rgb(flutterFill[1].slice(2)), parseInt(flutterFill[1].slice(0, 2), 16) / 255]];
  for (const [fill, alpha] of fills) {
    for (const backdrop of ['000000', 'ffffff', '590219', '77d9d9', '588c8c', '8c7326', 'a6806a']) {
      for (const foreground of ['590219', '355757']) {
        const ratio = contrast(rgb(foreground), composite(fill, alpha, rgb(backdrop)));
        assert.ok(ratio >= 4.5, `${foreground} on fill ${fill}/${alpha} over ${backdrop}: ${ratio}`);
      }
    }
  }
});

test('primary label and solid-plot strokes meet text and non-text contrast', () => {
  assert.ok(contrast(rgb('ffffff'), rgb('590219')) >= 4.5);
  for (const stroke of ['590219', '588c8c', '355757']) assert.ok(contrast(rgb(stroke), rgb('ffffff')) >= 3);
});

test('measured gauge edge remains visible against aqua fill and rail endpoints', () => {
  const gauge = readFileSync(new URL('../../apps/client/lib/widgets/volume_gauge.dart', import.meta.url), 'utf8');
  const edgeToken = gauge.match(/top: BorderSide\(color: (\w+), width: 3\)/)?.[1];
  assert.ok(edgeToken, '3px measured edge exists');
  assert.match(dart, new RegExp(`${edgeToken} = Color\\(0xff590219\\)`));
  for (const adjacent of ['77d9d9', 'd6ebe8', 'f7faf6']) {
    assert.ok(contrast(rgb('590219'), rgb(adjacent)) >= 3);
  }
});
