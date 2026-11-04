// Task-relative practice prompts, not grades or a model of natural speech.
// K-ToBI describes possible Korean intonation shapes; it does not provide the
// numerical support limits below or a unique correct contour for a script.
import { summarizeComparison } from './audio-analysis.js';

export const EVIDENCE = Object.freeze({
  url: 'https://sunahjun.humspace.ucla.edu/ktobi/K-tobi.html',
  title: 'K-ToBI: 한국어 억양의 형태 (§1.1, §3.3)',
  scope: '올라가기·내려가기 형태를 연습 목표로 선택하는 데 참고했어요.',
  note: '같은 문장도 여러 억양으로 말할 수 있어요. 이 문서는 정답 곡선이나 합격 기준을 정하지 않아요.',
});

// Engineering safeguards for estimating two endpoint-region medians. These
// are not normal ranges, perceptual thresholds, or clinically validated rules.
const MIN_FRAMES = 5;
const MIN_SPAN = 0.12;
const MIN_ENDPOINT_FRAMES = 3;
const MIN_ENDPOINT_SPAN = 0.04;
const MAX_ENDPOINT_GAP = 0.08;
const EPS = 1e-8;
const ROUNDING_NOTE = '수치는 0.1 단위로 반올림했어요. 실제 목소리가 잡힌 앞·뒤 대표 구간의 비교이며 중간 흐름 전체를 뜻하지 않아요.';

function median(values) {
  const sorted = values.filter(Number.isFinite).sort((a, b) => a - b);
  if (!sorted.length) return null;
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

function rounded(value) {
  const result = Number(value.toFixed(1));
  return Object.is(result, -0) ? 0 : result;
}

function direction(value) {
  const shown = rounded(value);
  return shown > 0 ? 'rise' : shown < 0 ? 'fall' : 'rounded-zero';
}

function validRange(start, end) {
  return Number.isFinite(start) && Number.isFinite(end) && start >= 0 && end > start;
}

function validFrame(frame, field) {
  return frame?.active === true && Number.isFinite(frame.time)
    && Number.isFinite(frame.pitchHz) && frame.pitchHz > 0 && Number.isFinite(frame[field]);
}

function hasSupport(points) {
  if (points.length < MIN_ENDPOINT_FRAMES || points.at(-1).time - points[0].time + EPS < MIN_ENDPOINT_SPAN) return false;
  for (let i = 1; i < points.length; i++) {
    if (points[i].time - points[i - 1].time > MAX_ENDPOINT_GAP + EPS) return false;
  }
  return true;
}

// A consonant or pause elsewhere in an endpoint band must not invalidate an
// independently measured block. Split on gaps without filling missing values.
function supportedBlocks(points) {
  const blocks = [];
  for (const frame of points) {
    if (!blocks.length || frame.time - blocks.at(-1).at(-1).time > MAX_ENDPOINT_GAP + EPS) blocks.push([]);
    blocks.at(-1).push(frame);
  }
  return blocks.filter(hasSupport);
}

function endpointChange(frames, start, end, field) {
  if (!Array.isArray(frames) || !validRange(start, end)) return null;
  // Keep one observation per timestamp as a second defence against repeated
  // DTW matches. Missing voice is never interpolated into the medians.
  const byTime = new Map();
  for (const frame of frames) {
    if (validFrame(frame, field) && frame.time >= start - EPS && frame.time <= end + EPS) byTime.set(frame.time, frame);
  }
  const points = [...byTime.values()].sort((a, b) => a.time - b.time);
  if (points.length < MIN_FRAMES || points.at(-1).time - points[0].time + EPS < MIN_SPAN) return null;
  const firstTime = points[0].time, lastTime = points.at(-1).time;
  const third = (lastTime - firstTime) / 3;
  const startBlocks = supportedBlocks(points.filter(frame => frame.time <= firstTime + third + EPS));
  const endBlocks = supportedBlocks(points.filter(frame => frame.time >= lastTime - third - EPS));
  if (!startBlocks.length || !endBlocks.length) return null;
  // Select the earliest/latest supported blocks by time only. Their pitch,
  // direction and agreement with another recording never select the windows.
  const first = startBlocks[0], last = endBlocks.at(-1);
  if (first.at(-1).time >= last[0].time - EPS) return null;
  const startValue = median(first.map(frame => frame[field]));
  const endValue = median(last.map(frame => frame[field]));
  const delta = endValue - startValue;
  return {
    delta, displayDelta: rounded(delta), direction: direction(delta),
    startValue, endValue,
    windows: { first: [first[0].time, first.at(-1).time], last: [last[0].time, last.at(-1).time] },
  };
}

/** Choose guide-only time regions for preview and comparison. User pitch,
 * agreement and errors never select boundaries. These are not word positions. */
export function choosePracticeRegions(reference, { whole = false } = {}) {
  if (!Array.isArray(reference?.frames) || !Number.isFinite(reference.duration) || reference.duration <= 0) {
    return { regions: [], segmentationNote: '가이드를 준비하면 연습할 구간을 보여드려요.' };
  }
  const rangesFor = count => Array.from({ length: count }, (_, i) => ({
    label: count === 1 ? (whole ? '선택 구간 전체' : '전체 흐름')
      : count === 2 ? ['앞부분', '뒷부분'][i] : ['앞부분', '중간', '끝부분'][i],
    start: reference.duration * i / count,
    end: reference.duration * (i + 1) / count,
  }));
  const supports = range => endpointChange(reference.frames, range.start, range.end, 'relativePitch') !== null
    && endpointChange(reference.frames, range.start, range.end, 'relativeDb') !== null;
  let ranges = rangesFor(1), supported = false;
  for (const count of whole ? [1] : [3, 2, 1]) {
    const candidate = rangesFor(count);
    if (candidate.every(supports)) {
      ranges = candidate;
      supported = true;
      break;
    }
  }
  const segmentationNote = !supported
    ? '이 예시에서는 앞·뒤 변화를 안내할 자료가 부족해요. 전체 그래프를 보며 연습할 수 있어요.'
    : ranges.length === 3
      ? '앞·중간·끝은 예시의 시간을 나눈 연습 구간이에요. 단어나 음절을 인식한 결과는 아니에요.'
      : ranges.length === 2
        ? '예시의 목소리를 충분히 비교할 수 있도록 앞·뒤 두 구간으로 나눴어요.'
        : whole
          ? '선택한 구간을 잘게 나누지 않고 하나의 흐름으로 비교해요.'
          : '짧은 예시는 잘게 나누지 않고 전체 흐름을 비교해요.';
  return { regions: ranges, segmentationNote };
}

/** Matched support is still checked independently on BOTH sides afterwards. */
export function buildPracticeSummary(reference, user, comparison, { whole = false } = {}) {
  const { regions, segmentationNote } = choosePracticeRegions(reference, { whole });
  return summarizeComparison(reference, user, comparison, { ranges: regions, segmentationNote });
}

function unavailable(reason, target = null) {
  return {
    title: '변화를 확인하기 어려워요',
    observation: '선택한 구간의 앞쪽과 뒤쪽에서 비교할 목소리를 충분히 확인하지 못했어요.',
    action: '그래프와 녹음을 확인하고, 목소리가 잡힌 앞·뒤가 포함되도록 구간을 다시 선택해 보세요.',
    available: false, delta: null, displayDelta: null, target, reason,
  };
}

function describeChange(change, pitch) {
  const unit = pitch ? '반음' : 'dB';
  if (change.direction === 'rounded-zero') return `앞·뒤 대표값의 차이가 반올림하면 0.0${unit}이에요`;
  const amount = Math.abs(change.displayDelta).toFixed(1);
  const motion = pitch
    ? (change.direction === 'rise' ? '높아요' : '낮아요')
    : (change.direction === 'rise' ? '커요' : '작아요');
  return `뒤쪽의 대표 ${pitch ? '높이' : '상대 크기'}가 앞쪽보다 ${amount}${unit} ${motion}`;
}

function describeWindows(change) {
  const { first, last } = change.windows;
  return `앞 ${first[0].toFixed(2)}~${first[1].toFixed(2)}초, 뒤 ${last[0].toFixed(2)}~${last[1].toFixed(2)}초`;
}

function matchedData(reference, user, comparison, segment, field) {
  if (!Array.isArray(reference?.frames) || !Array.isArray(user?.frames) || !Array.isArray(comparison?.path)
    || !validRange(segment?.start, segment?.end) || !validRange(segment?.userStart, segment?.userEnd)) return null;
  const referenceFrames = new Map(), userFrames = new Map();
  const perReference = new Map(), perUser = new Map();
  const seenPairs = new Set();
  for (const pair of comparison.path) {
    if (!Array.isArray(pair) || !Number.isInteger(pair[0]) || !Number.isInteger(pair[1])) continue;
    const [ri, ui] = pair, a = reference.frames[ri], b = user.frames[ui];
    if (!validFrame(a, field) || !validFrame(b, field)
      || a.time < segment.start - EPS || a.time > segment.end + EPS
      || b.time < segment.userStart - EPS || b.time > segment.userEnd + EPS) continue;
    const key = `${ri}:${ui}`;
    if (seenPairs.has(key)) continue;
    seenPairs.add(key);
    referenceFrames.set(ri, a); userFrames.set(ui, b);
    const offset = b[field] - a[field];
    const rValues = perReference.get(ri) || []; rValues.push(offset); perReference.set(ri, rValues);
    const uValues = perUser.get(ui) || []; uValues.push(offset); perUser.set(ui, uValues);
  }
  // Use the actual matched support on BOTH sides. One fixed time-third may
  // begin with an unvoiced consonant; using that blank margin only on the
  // reference side would give different endpoint windows even for self audio.
  const supportedChange = map => {
    const frames = [...map.values()].sort((a, b) => a.time - b.time);
    if (!frames.length) return null;
    return endpointChange(frames, frames[0].time, frames.at(-1).time, field);
  };
  const r = supportedChange(referenceFrames);
  const u = supportedChange(userFrames);
  if (!r || !u) return null;
  const rOffset = median([...perReference.values()].map(median));
  const uOffset = median([...perUser.values()].map(median));
  return { reference: r, user: u, relativeOffset: (rOffset + uOffset) / 2 };
}

/** Describe one matched time interval. Its label does not identify a word.
 * The change uses each recording's chronological UNIQUE matched frames.
 * A static vertical offset and an absolute error must never determine motion.
 */
export function describeSegmentPractice(reference, user, comparison, segment, tab = 'pitch') {
  const pitch = tab === 'pitch', field = pitch ? 'relativePitch' : 'relativeDb';
  const data = matchedData(reference, user, comparison, segment, field);
  if (!data) return {
    ...unavailable('insufficient-endpoint-support'),
    tone: 'uncertain', icon: '?', cardLabel: '비교 자료 부족',
    title: '이 부분은 같이 살펴볼까요?',
    observation: '앱이 이 부분의 처음과 끝을 충분히 비교하지 못했어요.',
    action: '그래프를 보며 이 부분을 조금 더 길게 읽어 볼까요? 편한 속도로 해 주세요.',
    detail: '서로 겹치지 않는 앞·뒤 음성 구간이 필요해요. 없는 목소리 값을 채우거나 성공·실패로 판단하지 않았어요.',
  };
  const r = data.reference, u = data.user;
  const regionLabel = typeof segment.label === 'string' && segment.label.trim() ? segment.label : '이 부분';
  const sameDirection = r.direction !== 'rounded-zero' && r.direction === u.direction;
  const opposite = r.direction !== 'rounded-zero' && u.direction !== 'rounded-zero' && r.direction !== u.direction;
  const qualitative = change => {
    if (change.direction === 'rounded-zero') return '처음과 끝의 차이가 작게 표시됐어요';
    const motion = pitch ? (change.direction === 'rise' ? '높아요' : '낮아요')
      : (change.direction === 'rise' ? '커요' : '작아요');
    return `끝의 ${pitch ? '음이' : '소리가'} 처음보다 ${motion}`;
  };
  let tone = 'neutral', title = '내 목소리의 흐름을 같이 살펴봐요', cardLabel = '함께 살펴봐요';
  let observation = `이번에는 ${qualitative(u)}. 중간의 움직임은 그래프에서 함께 볼 수 있어요.`;
  let action = '파란 선과 짙은 회색 선을 나란히 봐 주세요. 더 연습하고 싶은 부분이 있다면, 그 부분만 다시 읽어도 좋아요.';
  if (sameDirection) {
    const reading = pitch ? (u.direction === 'rise' ? '올려' : '내려')
      : (u.direction === 'rise' ? '크게' : '작게');
    tone = 'encourage'; title = `좋아요! 끝을 ${reading} 읽었네요.`;
    cardLabel = pitch ? (u.direction === 'rise' ? '끝을 올렸어요' : '끝을 내렸어요') : `끝을 ${reading} 읽었어요`;
    observation = `${regionLabel}에서 ${qualitative(u)}. 파란 예시도 같은 쪽으로 움직여요.`;
    action = '지금처럼 편하게 읽어 보세요. 다음 부분도 같이 해 볼까요?';
  } else if (opposite || (r.direction !== 'rounded-zero' && u.direction === 'rounded-zero')) {
    tone = 'practice'; title = '끝부분만 조금 바꿔 볼까요?'; cardLabel = '조금씩 연습해요';
    observation = `${regionLabel}에서 ${qualitative(u)}. 파란 예시는 ${qualitative(r)}.`;
    const movement = pitch ? (r.direction === 'rise' ? '높여서' : '낮춰서')
      : (r.direction === 'rise' ? '키워서' : '줄여서');
    action = `파란 선을 보면서 끝 ${pitch ? '음을' : '소리를'} 조금 ${movement} 읽어 볼까요? 편하게 한 번 더 해 봐요.`;
  }
  const note = `${ROUNDING_NOTE}${pitch ? '' : ' 크기는 각 녹음의 기준 크기에 대한 값이며 실제 소음계 데시벨이 아니에요.'}`;
  return {
    tone, icon: u.direction === 'rise' ? '↗' : u.direction === 'fall' ? '↘' : '↔', cardLabel,
    title, observation,
    action, available: true,
    referenceDelta: r.delta, userDelta: u.delta, delta: u.delta, displayDelta: u.displayDelta,
    referenceDirection: r.direction, userDirection: u.direction,
    relativeOffset: data.relativeOffset,
    detail: `예시는 ${describeChange(r, pitch)}. 내 녹음은 ${describeChange(u, pitch)}. 측정 구간: 예시 ${describeWindows(r)} / 내 녹음 ${describeWindows(u)}. ${note}`,
    note,
    windows: { reference: r.windows, user: u.windows },
  };
}

/** Coach an explicitly chosen rise/fall task in an explicitly chosen interval.
 * No script, punctuation, word boundary, or intended meaning is inferred.
 */
export function describeGoal(analysis, { start, end, target } = {}) {
  if (target !== 'rise' && target !== 'fall') return unavailable('missing-explicit-target');
  const change = endpointChange(analysis?.frames, start, end, 'relativePitch');
  if (!change) return unavailable('insufficient-endpoint-support', target);
  const targetText = target === 'rise' ? '시작보다 끝을 높이기' : '시작보다 끝을 낮추기';
  const movement = target === 'rise' ? '높여서' : '낮춰서';
  let action;
  if (change.direction === 'rounded-zero') {
    action = `이번 목표는 ${targetText}예요. 선택한 구간을 다시 듣고, 끝의 음을 ${movement} 읽는 연습을 해 보세요.`;
  } else if (change.direction !== target) {
    action = `이번 목표는 ${targetText}예요. 선택한 구간만 시작보다 끝의 음을 ${movement} 다시 읽어 보세요.`;
  } else {
    action = '선택한 구간의 앞·뒤를 번갈아 듣고, 이번에 만든 높낮이 변화를 다시 시도해 보세요.';
  }
  return {
    title: `연습 목표: ${targetText}`,
    observation: `선택한 시간 구간은 ${describeChange(change, true)}.`,
    action, available: true, delta: change.delta, displayDelta: change.displayDelta,
    target, direction: change.direction, windows: change.windows, note: ROUNDING_NOTE,
  };
}
