const COLORS = { guide: '#2f62d6', voice: '#34455e', text: '#465a74', grid: '#dce5f2' };

const validRegions = regions => Array.isArray(regions) ? regions.filter(region => region
  && Number.isFinite(region.start) && Number.isFinite(region.end)
  && region.start >= 0 && region.end > region.start) : [];

function geometry(width) {
  const height = Math.max(255, Math.min(350, width * .58));
  return { width, height, left: 48, right: width - 12, top: width < 320 ? 48 : 30, bottom: height - 51 };
}

/** Returns the supplied time-region index, never an inferred word position.
 * With no displayed regions there is no selection to invent from a click. */
export function graphSegmentAt(canvas, reference, clientX, clientY, regions = []) {
  if (!reference?.duration) return null;
  const actual = validRegions(regions);
  if (!actual.length) return null;
  const rect = canvas.getBoundingClientRect();
  if (!rect.width || !rect.height) return null;
  const g = geometry(canvas.clientWidth || rect.width);
  const x = (clientX - rect.left) * g.width / rect.width;
  const y = (clientY - rect.top) * g.height / rect.height;
  if (x < g.left || x > g.right || y < g.top || y > g.height) return null;
  const time = (x - g.left) / (g.right - g.left) * reference.duration;
  const index = actual.findIndex((region, i) => time >= region.start
    && (time < region.end || (i === actual.length - 1 && time <= region.end)));
  return index < 0 ? null : regions.indexOf(actual[index]);
}

export function drawGraph(canvas, { reference, trace = [], field = 'relativePitch', progress = null, selected = null, regions = [], empty = false, timeAxis = false, live = false, domainSeconds = null, scaleBound = null }) {
  const g = geometry(canvas.clientWidth || 500);
  const { width, height, left, right, top, bottom } = g;
  const scale = Math.min(3, Math.max(2, globalThis.devicePixelRatio || 1));
  canvas.width = Math.round(width * scale);
  canvas.height = Math.round(height * scale);
  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  ctx.scale(scale, scale);
  ctx.clearRect(0, 0, width, height);
  const referenceFrames = reference?.frames || [];
  const values = [...referenceFrames, ...trace].map(f => f[field]).filter(Number.isFinite);
  const isPitch = field === 'relativePitch';
  // Keep measured values in view with headroom; never clamp a peak into a flat line.
  const bound = Math.max(isPitch ? 5 : 10, Number.isFinite(scaleBound) && scaleBound > 0 ? scaleBound : 0,
    ...values.map(v => Math.abs(v) * 1.12));
  const traceEnd = Math.max(0, ...trace.map(frame => frame.time).filter(Number.isFinite));
  const domain = Math.max(reference?.duration || 0, traceEnd,
    Number.isFinite(domainSeconds) && domainSeconds > 0 ? domainSeconds : 0, .1);
  const actualRegions = live || empty ? [] : validRegions(regions);
  const showTime = timeAxis || live || !actualRegions.length;
  const regionDuration = live ? domain : reference?.duration || domain;
  const x = time => left + Math.max(0, Math.min(1, time / domain)) * (right - left);
  const y = value => (top + bottom) / 2 - value / bound * (bottom - top) / 2;
  const selectedIndex = selected ? actualRegions.findIndex(region => region.start === selected.start && region.end === selected.end) : -1;

  ctx.font = '600 12px Pretendard, sans-serif';
  ctx.textBaseline = 'middle';
  ctx.textAlign = 'left';
  ctx.fillStyle = '#38567e';
  ctx.fillText(isPitch ? '음 높이' : '소리 크기', left, 13);
  ctx.font = '12px Pretendard, sans-serif';
  ctx.textAlign = 'right';
  ctx.fillStyle = '#465a74';
  ctx.fillText(live ? '기준: 녹음 중 갱신' : '기준: 각 목소리의 중간값', right, width < 320 ? 30 : 13, right - 4);

  const backgroundRegions = actualRegions.length ? actualRegions : [{ start: 0, end: regionDuration }];
  for (let i = 0; i < backgroundRegions.length; i++) {
    const start = x(backgroundRegions[i].start), end = x(backgroundRegions[i].end);
    ctx.fillStyle = i === selectedIndex ? '#eaf1fe' : i % 2 ? '#f8fafc' : '#f0f5fc';
    ctx.fillRect(start, top, end - start, bottom - top);
  }
  if(selected&&selectedIndex<0){ctx.fillStyle='#eaf1fe';ctx.fillRect(x(selected.start),top,x(selected.end)-x(selected.start),bottom-top);}
  ctx.lineWidth = 1;
  ctx.strokeStyle = COLORS.grid;
  for (const position of [top, bottom]) {
    ctx.beginPath(); ctx.moveTo(left, position); ctx.lineTo(right, position); ctx.stroke();
  }
  // A visible zero line explains the relative scale without technical tick values.
  ctx.strokeStyle = '#a8b8cf';
  ctx.setLineDash([4, 5]);
  ctx.beginPath(); ctx.moveTo(left, y(0)); ctx.lineTo(right, y(0)); ctx.stroke();
  ctx.setLineDash([]);
  const boundaries = actualRegions.length
    ? [...new Set(actualRegions.flatMap(region => [region.start, region.end]))]
    : [0, regionDuration / 2, regionDuration];
  for (const boundary of boundaries) {
    const xx = x(boundary);
    ctx.strokeStyle = '#d6e1ef'; ctx.beginPath(); ctx.moveTo(xx, top); ctx.lineTo(xx, bottom); ctx.stroke();
  }
  // Live position is elapsed recording time, not an inferred word position.
  // Keep the reference endpoint visible when the live time window is longer.
  if (live && Number.isFinite(reference?.duration) && reference.duration > 0) {
    const endX = x(reference.duration);
    if (endX > left + 12 && endX < right - 2) {
      ctx.strokeStyle = '#94b6ec'; ctx.lineWidth = 1; ctx.setLineDash([3, 5]);
      ctx.beginPath(); ctx.moveTo(endX, top); ctx.lineTo(endX, bottom); ctx.stroke(); ctx.setLineDash([]);
      ctx.font = '12px Pretendard, sans-serif'; ctx.fillStyle = '#52647b';
      if (right - endX > 64) { ctx.textAlign = 'left'; ctx.fillText('가이드 끝', endX + 5, top + 22); }
      else if (endX - left > 64) { ctx.textAlign = 'right'; ctx.fillText('가이드 끝', endX - 5, top + 22); }
    }
  }

  ctx.fillStyle = COLORS.text;
  ctx.font = '600 12px Pretendard, sans-serif';
  ctx.textAlign = 'right';
  ctx.fillText(isPitch ? '높음' : '큼', left - 10, top + 5);
  ctx.font = '12px Pretendard, sans-serif';
  ctx.fillStyle = '#465a74'; ctx.fillText('기준', left - 10, y(0));
  ctx.fillStyle = COLORS.text;
  ctx.font = '600 12px Pretendard, sans-serif';
  ctx.fillText(isPitch ? '낮음' : '작음', left - 10, bottom - 4);

  // Every null breaks the stroke. White underlays improve contrast without
  // smoothing or connecting unmeasured sections. Draw both colours afterwards
  // so the wider dashed guide remains visible around an overlapping user line.
  const measured = frame => Number.isFinite(frame?.time) && Number.isFinite(frame?.[field]);
  function line(frames, color, dash, lineWidth) {
    ctx.beginPath(); ctx.strokeStyle = color; ctx.lineWidth = lineWidth;
    ctx.lineJoin = 'round'; ctx.lineCap = 'round'; ctx.setLineDash(dash);
    let drawing = false;
    for (const frame of frames) {
      const value = frame[field];
      if (!measured(frame)) { drawing = false; continue; }
      if (drawing && !frame.breakBefore) ctx.lineTo(x(frame.time), y(value));
      else ctx.moveTo(x(frame.time), y(value));
      drawing = true;
    }
    ctx.stroke(); ctx.setLineDash([]);
  }
  line(referenceFrames, '#ffffff', [10, 7], 8);
  line(trace, '#ffffff', [], live ? 8 : 6.5);
  line(referenceFrames, COLORS.guide, [10, 7], live ? 3.5 : 4.8);
  line(trace, COLORS.voice, [], live ? 5 : 3.3);

  // moveTo-only paths do not paint a visible stroke. Show isolated measured
  // samples as points rather than connecting across missing speech. The live
  // marker exists only for the actual latest sample, never a stale voiced one.
  trace.forEach((frame, index) => {
    if (!measured(frame)) return;
    const current = live && index === trace.length - 1;
    const isolated = (!measured(trace[index - 1]) || frame.breakBefore) &&
      (!measured(trace[index + 1]) || trace[index + 1].breakBefore);
    if (!current && !isolated) return;
    const radius = current ? 6 : 3.5;
    ctx.beginPath(); ctx.fillStyle = '#ffffff'; ctx.arc(x(frame.time), y(frame[field]), radius + 2, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.fillStyle = COLORS.voice; ctx.arc(x(frame.time), y(frame[field]), radius, 0, Math.PI * 2); ctx.fill();
  });

  if (selected) {
    const start = x(selected.start), end = x(selected.end);
    ctx.strokeStyle = '#7c9fe0'; ctx.lineWidth = 1.8;
    ctx.strokeRect(start + 1, top + 1, Math.max(0, end - start - 2), bottom - top - 2);
  }
  ctx.font = '600 14px Pretendard, sans-serif';
  ctx.textAlign = 'center';
  const labels = showTime
    ? [0, regionDuration / 2, regionDuration].map(time => ({ time, label: `${time.toFixed(1)}초`, selected: false }))
    : actualRegions.map((region, i) => ({ time: (region.start + region.end) / 2, label: region.label, selected: i === selectedIndex }));
  for (const label of labels) {
    const xx = x(label.time);
    ctx.fillStyle = label.selected ? '#244f8b' : '#526b8d';
    ctx.fillText(label.label, xx, bottom + 21);
    if (label.selected) {
      ctx.fillStyle = '#244f8b';
      ctx.font = '12px Pretendard, sans-serif';
      ctx.fillText('선택한 구간', xx, bottom + 38);
      ctx.font = '600 14px Pretendard, sans-serif';
    }
  }

  if (Number.isFinite(progress)) {
    const latestMeasured = measured(trace.at(-1));
    const cursorColor = live ? (latestMeasured ? COLORS.voice : '#52647b') : COLORS.guide;
    const tagHalfWidth = live ? (latestMeasured ? 34 : 43) : 23;
    const xx = x(progress), tagX = Math.min(right - tagHalfWidth, Math.max(left + tagHalfWidth, xx));
    ctx.beginPath(); ctx.strokeStyle = cursorColor; ctx.lineWidth = 2;
    ctx.moveTo(xx, top); ctx.lineTo(xx, bottom); ctx.stroke();
    ctx.fillStyle = cursorColor; ctx.fillRect(tagX - tagHalfWidth, top - 4, tagHalfWidth * 2, 22);
    ctx.fillStyle = '#fff'; ctx.font = '600 12px Pretendard, sans-serif';
    ctx.fillText(live ? (latestMeasured ? '내 목소리' : '소리 확인 중') : '지금', tagX, top + 7);
  }
  if (empty || !values.length) {
    ctx.fillStyle = '#fffffff0'; ctx.fillRect(left, top, right - left, bottom - top);
    ctx.fillStyle = '#526b8d'; ctx.textAlign = 'center';
    ctx.font = '600 14px Pretendard, sans-serif';
    ctx.fillText(reference ? '녹음 후 두 선을 비교해요' : '녹음하면 내 목소리가 나타나요', (left + right) / 2, (top + bottom) / 2 - 12);
    ctx.font = '12px Pretendard, sans-serif';
    ctx.fillStyle = '#465a74';
    ctx.fillText('확인할 수 없는 소리는 선을 비워 둬요', (left + right) / 2, (top + bottom) / 2 + 13);
  }
}
