// A manually chosen TIME excerpt, never a detected word or syllable.
// Its baseline must match the independently normalized repeat recording;
// otherwise selecting a high/low part of a phrase creates a false offset.
const FRAME_HOP_SECONDS = 0.02; // audio-analysis.js offline analysis hop
const EPSILON = 1e-9;

function median(values) {
  const sorted = values.filter(Number.isFinite).sort((a, b) => a - b);
  if (!sorted.length) return null;
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/** Convert a trimmed-analysis interval to original-audio playback seconds.
 * Context and the short-clip limit are listening conveniences, not evaluation
 * thresholds. Padding reduces abrupt cuts; it cannot locate words or guarantee
 * a phonetic boundary. `context` reports the requested padding, whose actual
 * length may be smaller at the file edges. A short file plays in full.
 */
export function playbackRange(analysis, { start, end } = {}, { context = .25, wholeBelow = 1.8 } = {}) {
  const duration = analysis?.duration;
  const offset = analysis?.startTime ?? 0;
  const sourceDuration = analysis?.sourceDuration ?? analysis?.recordingDuration
    ?? (Number.isFinite(duration) && Number.isFinite(offset) ? offset + duration : NaN);
  if (!Number.isFinite(duration) || duration <= 0 || !Number.isFinite(offset) || offset < 0
    || !Number.isFinite(sourceDuration) || sourceDuration <= 0) {
    throw new Error('재생할 원본 음성의 시간 정보를 확인해 주세요.');
  }
  if (!Number.isFinite(start) || !Number.isFinite(end) || start < 0 || end <= start
    || end > duration + EPSILON) throw new Error('음성 안에서 시작보다 뒤에 있는 끝 시간을 골라 주세요.');
  if (!Number.isFinite(context) || context < 0 || !Number.isFinite(wholeBelow) || wholeBelow < 0) {
    throw new Error('재생 여유 시간은 0 이상의 유한한 값이어야 해요.');
  }
  // startTime already points to the original file, including nested excerpts.
  // Apply it once; do not add the parent excerpt's offset a second time.
  const coreStart = Math.min(sourceDuration, offset + start);
  const coreEnd = Math.min(sourceDuration, offset + Math.min(duration, end));
  if (coreEnd <= coreStart) throw new Error('선택한 구간이 원본 음성 범위를 벗어났어요.');
  const whole = sourceDuration <= wholeBelow;
  return {
    coreStart, coreEnd,
    start: whole ? 0 : Math.max(0, coreStart - context),
    end: whole ? sourceDuration : Math.min(sourceDuration, coreEnd + context),
    whole, context,
  };
}

/** Crop an existing guide to an explicit time range without re-detecting voice
 * or connecting gaps. Region coordinates refer to the supplied guide analysis.
 * startTime remains an offset into the SAME original audioUrl for playback.
 */
export function cropReference(guide, { start, end, label = '선택한 구간' } = {}) {
  const source = guide?.analysis;
  if (!Array.isArray(source?.frames) || !Number.isFinite(source.duration) || source.duration <= 0) {
    throw new Error('연습할 가이드 음성을 먼저 준비해 주세요.');
  }
  if (!Number.isFinite(start) || !Number.isFinite(end) || start < 0 || end <= start
    || end > source.duration + EPSILON) {
    throw new Error('가이드 안에서 시작보다 뒤에 있는 끝 시간을 골라 주세요.');
  }
  const boundedEnd = Math.min(end, source.duration), duration = boundedEnd - start;
  const frames = source.frames.filter(frame => Number.isFinite(frame.time)
    && frame.time >= start - EPSILON && frame.time <= boundedEnd + EPSILON).map(frame => {
    const active = frame.active === true && Number.isFinite(frame.pitchHz) && frame.pitchHz > 0 && Number.isFinite(frame.rmsDb);
    return { ...frame, time: Math.max(0, Math.min(duration, frame.time - start)), active,
      pitchHz: active ? frame.pitchHz : null, relativePitch: null, relativeDb: null };
  });
  const activeFrames = frames.filter(frame => frame.active);
  const pitchMedian = median(activeFrames.map(frame => frame.pitchHz));
  const levelMedian = median(activeFrames.map(frame => frame.rmsDb));
  if (activeFrames.length < 8 || !pitchMedian || levelMedian === null) {
    throw new Error('이 구간에서 비교할 목소리가 충분하지 않아요. 조금 더 넓은 구간을 골라 주세요.');
  }
  for (const frame of frames) {
    if (!frame.active) continue;
    frame.relativePitch = 12 * Math.log2(frame.pitchHz / pitchMedian);
    frame.relativeDb = frame.rmsDb - levelMedian;
  }
  const voicedFrames = activeFrames.length, voicedDuration = Math.min(duration, voicedFrames * FRAME_HOP_SECONDS);
  return { ...guide, region: { start, end: boundedEnd, label }, analysis: {
    ...source, frames, duration, recordingDuration: duration,
    sourceDuration: source.sourceDuration ?? source.recordingDuration
      ?? (Number.isFinite(source.startTime) ? source.startTime : 0) + source.duration,
    startTime: (Number.isFinite(source.startTime) ? source.startTime : 0) + start,
    pitchMedian, levelMedian, voicedFrames, voicedDuration,
    voicedFraction: frames.length ? voicedFrames / frames.length : 0,
    excludedDuration: Math.max(0, duration - voicedDuration),
  } };
}
