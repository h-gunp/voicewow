import test from 'node:test';
import assert from 'node:assert/strict';
import { drawGraph, graphSegmentAt } from '../../apps/client/web/prosody/charts.js';
import { alignedTrace } from '../../apps/client/web/prosody/lab-utils.js';

// Observe actual canvas drawing operations, without a browser or microphone.
// A path containing only moveTo has no painted line; filled arcs do paint.
function canvas() {
  const painted = [], text = [], rectangles = [];
  let path = [], dash = [];
  const ctx = {
    scale() {}, clearRect() {},
    beginPath() { path = []; },
    moveTo(x, y) { path.push({ type: 'move', x, y }); },
    lineTo(x, y) { path.push({ type: 'line', x, y }); },
    arc(x, y, radius) { path.push({ type: 'arc', x, y, radius }); },
    setLineDash(value) { dash = [...value]; },
    stroke() { painted.push({ kind: 'stroke', color: this.strokeStyle, width: this.lineWidth, dash, path: [...path] }); },
    fill() { painted.push({ kind: 'fill', color: this.fillStyle, path: [...path] }); },
    fillRect(x, y, width, height) { rectangles.push({ color: this.fillStyle, x, y, width, height }); },
    strokeRect() {},
    fillText(value, x, y) { text.push({ value, color: this.fillStyle, x, y }); },
  };
  return { clientWidth: 400, getContext: () => ctx,
    getBoundingClientRect: () => ({ left: 0, top: 0, width: 400, height: 255 }),
    painted, text, rectangles };
}

const frame = (time, value) => ({ time, relativePitch: value, relativeDb: value });
const reference = { duration: 2, frames: [frame(0, -1), frame(1, 1), frame(2, 0)] };
const voiceColor = '#590219';
const dots = c => c.painted.filter(p => p.kind === 'fill' && p.color === voiceColor).flatMap(p => p.path.filter(op => op.type === 'arc'));
const voicePath = c => c.painted.find(p => p.kind === 'stroke' && p.color === voiceColor)?.path;

test('isolated measured voice samples remain visible without bridging missing pitch', () => {
  const c = canvas();
  drawGraph(c, { reference, trace: [frame(0, 1), frame(.02, null), frame(.04, -1), frame(.06, null), frame(.08, 2)], live: true });
  assert.equal(dots(c).length, 3, 'all isolated real measurements must paint a visible point');
  assert.ok(voicePath(c).every(op => op.type === 'move'), 'no stroke may bridge missing observations');
  const result = canvas();
  drawGraph(result, { reference, trace: [frame(.5, 0)] });
  assert.equal(dots(result).length, 1, 'one-point observations also remain visible after recording');
});

test('live voice uses a visible foreground stroke and a marker on the actual latest sample', () => {
  const c = canvas();
  drawGraph(c, { reference, trace: [frame(0, -1), frame(.04, 1)], live: true, progress: .04 });
  assert.equal(dots(c).length, 1);
  const voiceStroke = c.painted.find(p => p.kind === 'stroke' && p.color === voiceColor);
  const haloStroke = c.painted.find(p => p.kind === 'stroke' && p.color === '#ffffff' && p.dash.length === 0);
  assert.ok(voiceStroke.width >= 5 && haloStroke.width > voiceStroke.width, 'live voice needs a strong visible edge over the guide');
  assert.ok(c.text.some(label => label.value === '내 목소리'));
  assert.ok(c.rectangles.some(rectangle => rectangle.color === voiceColor), 'live cursor follows the voice color');
});

test('a missing latest pitch does not leave an old point looking like current voice', () => {
  const c = canvas();
  drawGraph(c, { reference, trace: [frame(0, 1), frame(.04, 2), frame(.08, null)], live: true, progress: .08 });
  assert.equal(dots(c).length, 0, 'the previous connected sample must not get a stale live marker');
  assert.ok(c.text.some(label => label.value === '소리 확인 중'));
  assert.ok(!c.text.some(label => label.value === '내 목소리'));
  assert.ok(!c.rectangles.some(rectangle => rectangle.color === voiceColor));
  assert.deepEqual(voicePath(c).map(op => op.type), ['move', 'line']);
});

test('live horizontal labels show elapsed seconds and the reference end, not inferred phrase positions', () => {
  const c = canvas();
  drawGraph(c, { reference, trace: [frame(.5, 0)], live: true, domainSeconds: 4 });
  const labels = c.text.map(label => label.value);
  assert.ok(labels.includes('0.0초') && labels.includes('2.0초') && labels.includes('4.0초'));
  assert.ok(labels.includes('가이드 끝'));
  assert.ok(!labels.some(label => ['앞부분', '중간', '끝부분'].includes(label)));
  assert.ok(labels.includes('기준: 녹음 중 갱신'));
});

test('provided live scale and time window keep earlier measured coordinates stable as samples arrive', () => {
  const first = canvas(), later = canvas();
  const options = { reference, live: true, domainSeconds: 4, scaleBound: 12 };
  drawGraph(first, { ...options, trace: [frame(.5, 2)] });
  drawGraph(later, { ...options, trace: [frame(.5, 2), frame(.6, 3)] });
  const before = dots(first)[0], after = voicePath(later)[0];
  assert.equal(before.x, after.x);
  assert.equal(before.y, after.y);
});

test('undersized or invalid overrides cannot clip measured peaks or later recording time', () => {
  for (const field of ['relativePitch', 'relativeDb']) {
    const c = canvas();
    drawGraph(c, { reference, trace: [frame(3, 25)], field, live: true, domainSeconds: 1, scaleBound: 1 });
    const point = dots(c)[0];
    assert.ok(point.x <= 388 && point.x > 48, 'later time must fit the drawing window');
    assert.ok(point.y > 30 && point.y < 204, 'a measured peak must remain inside the plot with headroom');
    const invalid = canvas();
    drawGraph(invalid, { reference, trace: [frame(3, 25)], field, live: true, domainSeconds: NaN, scaleBound: -1 });
    assert.ok(dots(invalid).every(dot => Number.isFinite(dot.x) && Number.isFinite(dot.y)));
  }
});

test('guide or empty graphs show seconds until actual supported regions are supplied', () => {
  const c = canvas();
  drawGraph(c, { reference });
  const labels = c.text.map(t => t.value);
  assert.ok(labels.includes('0.0초') && labels.includes('1.0초') && labels.includes('2.0초'));
  assert.ok(!labels.some(label => ['앞부분', '중간', '끝부분'].includes(label)));
  assert.equal(graphSegmentAt(c, reference, 200, 100), null);
});

test('graph labels, shading and hit testing use the actual supplied time ranges rather than fixed thirds', () => {
  const regions = [{ label: '짧은 앞 구간', start: 0, end: .5 }, { label: '남은 구간', start: .5, end: 2 }];
  const c = canvas();
  drawGraph(c, { reference, regions, selected: regions[0] });
  const labels = c.text.map(t => t.value);
  assert.ok(labels.includes('짧은 앞 구간') && labels.includes('남은 구간'));
  assert.ok(!labels.includes('중간'));
  const highlighted = c.rectangles.find(rectangle => rectangle.color === '#dff3f1');
  assert.equal(highlighted.width, (388 - 48) / 4);
  assert.equal(graphSegmentAt(c, reference, 48 + (388 - 48) * .1, 100, regions), 0);
  assert.equal(graphSegmentAt(c, reference, 48 + (388 - 48) * .3, 100, regions), 1);
  assert.equal(graphSegmentAt(c, reference, 388, 100, regions), 1);
  assert.equal(graphSegmentAt(c, reference, 20, 100, regions), null);
});

test('single whole regions do not acquire extra front middle end labels', () => {
  const c = canvas(), regions = [{ label: '전체 흐름', start: 0, end: 2 }];
  drawGraph(c, { reference, regions, selected: regions[0] });
  const labels = c.text.map(t => t.value);
  assert.ok(labels.includes('전체 흐름'));
  assert.ok(!labels.some(label => ['앞부분', '중간', '끝부분'].includes(label)));
  assert.equal(graphSegmentAt(c, reference, 300, 100, regions), 0);
});

test('aligned result never connects across skipped user silence, including within one reference bucket',()=>{
  const ref={duration:3,frames:[frame(0,0),frame(1,1),frame(2,2),frame(3,3)]};
  const user={frames:[frame(0,0),frame(1,null),frame(2,2),frame(3,3)]};
  for(const [path,expected] of [[[[0,0],[1,2],[2,3]],['move','move','line']],[[[0,0],[0,2],[1,3]],['move']]]){
    const trace=alignedTrace(ref,user,path), c=canvas();
    drawGraph(c,{reference:ref,trace});
    const operations=voicePath(c);
    assert.deepEqual(operations.map(op=>op.type),expected,'stroke must not bridge the skipped user frame');
    assert.ok(dots(c).length>0,'isolated measurements remain visible');
  }
});


test('narrow chart places heading and explanatory text on separate rows above the plot', () => {
  const c = canvas(); c.clientWidth = 173;
  drawGraph(c, { reference });
  const title = c.text.find(item => item.value === '음 높이');
  const description = c.text.find(item => item.value === '기준: 각 목소리의 중간값');
  assert.ok(title && description);
  assert.ok(description.y - title.y >= 14, 'narrow headings must not share a row');
  const plot = c.rectangles.find(rect => rect.color === '#f0f7f5');
  assert.ok(plot.y >= description.y + 8, 'the plot must start below the description');
  c.getBoundingClientRect = () => ({left:0, top:0, width:173, height:255});
  const regions = [{label:'앞',start:0,end:1},{label:'뒤',start:1,end:2}];
  assert.equal(graphSegmentAt(c, reference, 80, 35, regions), null, 'header is outside the selectable plot');
  assert.equal(graphSegmentAt(c, reference, 80, 80, regions), 0);
});
