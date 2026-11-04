// Browser-only acoustic comparison. These measurements are NOT diagnoses or
// judgments of naturalness. No audio is sent or saved by this module.
const EPS = 1e-12;
const MIN_PITCH = 65;
const MAX_PITCH = 500;
const MIN_CLARITY = 0.85;
const MIN_LEVEL_DB = -65;
const HOP_SECONDS = 0.02;

function median(values) {
  const a = values.filter(Number.isFinite).sort((x, y) => x - y);
  if (!a.length) return null;
  const m = Math.floor(a.length / 2);
  return a.length % 2 ? a[m] : (a[m - 1] + a[m]) / 2;
}

// Decimation by local averaging keeps this lightweight for mobile browsers.
// 12–16 kHz is sufficient for the 65–500 Hz fundamental range used here.
function downsample(input, sampleRate) {
  const factor = Math.max(1, Math.floor(sampleRate / 12000));
  if (factor === 1) return { samples: input, sampleRate };
  const out = new Float32Array(Math.floor(input.length / factor));
  for (let i = 0; i < out.length; i++) {
    let sum = 0;
    for (let j = 0; j < factor; j++) {
      const value = input[i * factor + j];
      sum += Number.isFinite(value) ? value : 0;
    }
    out[i] = sum / factor;
  }
  return { samples: out, sampleRate: sampleRate / factor };
}

// YIN: a periodicity estimate, not a speaker identifier or voice-quality test.
function yin(frame, sampleRate) {
  const maxLag = Math.min(Math.floor(sampleRate / MIN_PITCH), Math.floor(frame.length / 2) - 1);
  const minLag = Math.max(2, Math.floor(sampleRate / MAX_PITCH));
  if (maxLag <= minLag) return { pitchHz: null, clarity: 0 };
  const difference = new Float64Array(maxLag + 1);
  const half = Math.floor(frame.length / 2);
  for (let lag = 1; lag <= maxLag; lag++) {
    let sum = 0;
    for (let i = 0; i < half; i++) {
      const d = frame[i] - frame[i + lag];
      sum += d * d;
    }
    difference[lag] = sum;
  }
  const cmnd = new Float64Array(maxLag + 1);
  cmnd[0] = 1;
  let running = 0;
  for (let lag = 1; lag <= maxLag; lag++) {
    running += difference[lag];
    cmnd[lag] = running > EPS ? difference[lag] * lag / running : 1;
  }
  let chosen = -1;
  for (let lag = minLag; lag < maxLag; lag++) {
    if (cmnd[lag] < 0.16) {
      while (lag + 1 <= maxLag && cmnd[lag + 1] < cmnd[lag]) lag++;
      chosen = lag;
      break;
    }
  }
  if (chosen < 0) return { pitchHz: null, clarity: 0 };
  const clarity = Math.max(0, Math.min(1, 1 - cmnd[chosen]));
  // Parabolic interpolation refines the minimum without inventing missing pitch.
  let refined = chosen;
  if (chosen > 1 && chosen < maxLag) {
    const a = cmnd[chosen - 1], b = cmnd[chosen], c = cmnd[chosen + 1];
    const denom = a - 2 * b + c;
    if (Math.abs(denom) > EPS) refined += Math.max(-0.5, Math.min(0.5, 0.5 * (a - c) / denom));
  }
  const pitchHz = sampleRate / refined;
  return { pitchHz: Number.isFinite(pitchHz) && pitchHz >= MIN_PITCH && pitchHz <= MAX_PITCH ? pitchHz : null, clarity };
}

// Optional noiseFloorDb comes from recent non-periodic live frames. This is a
// conservative acoustic gate, not speech recognition or speaker separation.
export function analyzeFrame(input, sampleRate, noiseFloorDb = null) {
  const reduced = downsample(input, sampleRate);
  const frame = reduced.samples;
  let energy = 0;
  for (const sample of frame) if (Number.isFinite(sample)) energy += sample * sample;
  const rmsDb = 20 * Math.log10(Math.max(1e-7, Math.sqrt(energy / Math.max(1, frame.length))));
  const floor = Number.isFinite(noiseFloorDb) ? Math.max(MIN_LEVEL_DB, noiseFloorDb + 6) : MIN_LEVEL_DB;
  const detected = rmsDb >= floor ? yin(frame, reduced.sampleRate) : { pitchHz: null, clarity: 0 };
  const active = detected.pitchHz !== null && detected.clarity >= MIN_CLARITY;
  return { ...detected, pitchHz: active ? detected.pitchHz : null, rmsDb, active };
}

export function trimAnalysis(analysis) {
  const active = analysis.frames.filter(f => f.active);
  if (!active.length) return { ...analysis, frames: [], duration: 0, startTime: 0 };
  const startTime = Math.max(0, active[0].time - 0.025);
  const endTime = Math.min(analysis.duration, active.at(-1).time + 0.025);
  return { ...analysis, startTime, duration: endTime - startTime,
    frames: analysis.frames.filter(f => f.time >= startTime && f.time <= endTime)
      .map(f => ({ ...f, time: f.time - startTime })) };
}

// Ranges describe times, never inferred syllable or word boundaries. The
// practice layer can supply a guide-only supported partition; this low-level
// summary must not choose a range from the user's pitch or comparison error.
export function summarizeComparison(reference, user, comparison, { whole = false, ranges = null, segmentationNote = '' } = {}) {
  const voiceDuration = a => a.voicedDuration ?? a.frames.filter(f => f.active && Number.isFinite(f.pitchHz)).length * HOP_SECONDS;
  const recordingDuration = a => a.recordingDuration ?? a.duration;
  const duration = { reference: voiceDuration(reference), user: voiceDuration(user),
    referenceRecording: recordingDuration(reference), userRecording: recordingDuration(user),
    referenceExcluded: Math.max(0, recordingDuration(reference) - voiceDuration(reference)),
    userExcluded: Math.max(0, recordingDuration(user) - voiceDuration(user)),
    referenceSpan: reference.duration, userSpan: user.duration };
  const matchedReferenceFrames = new Set(comparison.path.map(([ri]) => ri)).size;
  const matchedUserFrames = new Set(comparison.path.map(([, ui]) => ui)).size;
  const pitchReliable = comparison.voicedPairs >= 8 && matchedReferenceFrames >= 8 && matchedUserFrames >= 8;
  const selectedRanges = ranges ?? (whole
    ? [{label:'선택 구간 전체',start:0,end:reference.duration}]
    : ['앞부분', '중간', '끝부분'].map((label,index)=>({label,start:reference.duration*index/3,end:reference.duration*(index+1)/3})));
  const segments = selectedRanges.map(({label,start,end}) => {
    const matches = comparison.path.filter(([ri]) => reference.frames[ri].time >= start && reference.frames[ri].time <= end);
    function differences(field) {
      const perUserFrame = new Map();
      const perReferenceFrame = new Map();
      for (const [ri, ui] of matches) {
        const a = reference.frames[ri][field], b = user.frames[ui][field];
        if (!Number.isFinite(a) || !Number.isFinite(b)) continue;
        const values = perUserFrame.get(ui) || []; values.push(b - a); perUserFrame.set(ui, values);
        const referenceValues = perReferenceFrame.get(ri) || []; referenceValues.push(b - a); perReferenceFrame.set(ri, referenceValues);
      }
      if (perUserFrame.size < 5 || perReferenceFrame.size < 5) return { delta: null, error: null };
      const meanAbsolute = map => [...map.values()].reduce((sum, values) =>
        sum + values.reduce((n, value) => n + Math.abs(value), 0) / values.length, 0) / map.size;
      return { delta: median([...perUserFrame.values()].map(values => median(values))),
        error: (meanAbsolute(perUserFrame) + meanAbsolute(perReferenceFrame)) / 2 };
    }
    const times = matches.map(([, ui]) => user.frames[ui].time);
    const pitch = differences('relativePitch'), level = differences('relativeDb');
    return { label, start, end, userStart: times.length ? Math.min(...times) : 0,
      userEnd: times.length ? Math.max(...times) : 0,
      pitchDelta: pitchReliable ? pitch.delta : null, pitchError: pitchReliable ? pitch.error : null,
      levelDelta: level.delta, levelError: level.error, pairs: matches.length,
      matchedReferenceFrames: new Set(matches.map(([ri]) => ri)).size,
      matchedUserFrames: new Set(matches.map(([, ui]) => ui)).size };
  });
  return { segments, duration, pitchReliable, segmentationNote };
}

/** Analyze an AudioBuffer's mono Float32 samples. Returns an array of frames.
 * Times are seconds; pitchHz is null when an estimate is not reliable.
 * relativePitch is in semitones relative to the recording's voiced median;
 * relativeDb is relative to the recording's voiced median signal level.
 */
export function analyzeAudio(input, sampleRate) {
  if (!(input instanceof Float32Array) || !Number.isFinite(sampleRate) || sampleRate < 8000) {
    throw new TypeError('Float32Array audio and a sample rate of at least 8000 Hz are required.');
  }
  if (input.length / sampleRate > 30) throw new RangeError('연습 음성은 30초 이하로 녹음해 주세요.');
  const duration = input.length / sampleRate;
  const reduced = downsample(input, sampleRate);
  const signal = reduced.samples, rate = reduced.sampleRate;
  const windowSize = Math.max(2, Math.round(rate * 0.05));
  const hopSize = Math.max(1, Math.round(rate * HOP_SECONDS));
  const frames = [];
  for (let start = 0; start + windowSize <= signal.length; start += hopSize) {
    const frame = signal.subarray(start, start + windowSize);
    let sumSquares = 0;
    for (let i = 0; i < frame.length; i++) {
      const s = Number.isFinite(frame[i]) ? frame[i] : 0;
      sumSquares += s * s;
    }
    const rms = Math.sqrt(sumSquares / frame.length);
    const rmsDb = 20 * Math.log10(Math.max(rms, 1e-7));
    const detected = rmsDb < MIN_LEVEL_DB ? { pitchHz: null, clarity: 0 } : yin(frame, rate);
    frames.push({ time: (start + windowSize / 2) / rate, pitchHz: detected.pitchHz,
      clarity: detected.clarity, rmsDb, relativePitch: null, relativeDb: null, active: false });
  }
  // Estimate background from the quieter non-periodic frames. Capping the
  // adaptive floor keeps energetic unvoiced consonants from cutting off soft
  // vowels when a clip has no actual silence. A peak/click must not set the gate.
  const candidates = frames.filter(f => f.pitchHz !== null && f.clarity >= MIN_CLARITY);
  const nonPeriodicLevels = frames.filter(f => f.pitchHz === null || f.clarity < MIN_CLARITY)
    .map(f => f.rmsDb).sort((a, b) => a - b);
  const noiseFloor = nonPeriodicLevels.length >= 5 ? nonPeriodicLevels[Math.floor((nonPeriodicLevels.length - 1) * 0.2)] : null;
  const candidateLevel = median(candidates.map(f => f.rmsDb));
  const candidateLevels = candidates.map(f => f.rmsDb).sort((a, b) => a - b);
  // Use several strong frames rather than a whole-clip percentile: even a long
  // wait with a quiet periodic hum must not redefine the voice baseline.
  const upperVoiceLevel = median(candidateLevels.slice(-8)) ?? MIN_LEVEL_DB;
  // A much quieter periodic hum can pass YIN. A robust upper voice level
  // rejects sounds >30 dB below the phrase, without using a single loud peak.
  // Similar-level periodic noise still cannot be separated from voice here.
  const activeFloor = Math.max(MIN_LEVEL_DB, upperVoiceLevel - 30, noiseFloor !== null && candidateLevel !== null
    ? Math.min(noiseFloor + 6, candidateLevel - 20) : MIN_LEVEL_DB);
  for (const f of frames) {
    f.active = f.rmsDb >= activeFloor && f.pitchHz !== null && f.clarity >= MIN_CLARITY;
  }
  // Isolated 20–40 ms periodic detections are too weak for contour feedback.
  // Never fill gaps: an uncertain sound must not acquire an invented pitch.
  for (let start = 0; start < frames.length;) {
    if (!frames[start].active) { start++; continue; }
    let end = start + 1;
    while (end < frames.length && frames[end].active) end++;
    if (end - start < 3) for (let i = start; i < end; i++) frames[i].active = false;
    start = end;
  }
  for (const f of frames) {
    if (!f.active) f.pitchHz = null;
  }
  const pitchMedian = median(frames.map(f => f.pitchHz));
  // Using voiced frames for both baselines avoids silence skewing the baseline.
  const levelMedian = median(frames.filter(f => f.pitchHz !== null).map(f => f.rmsDb));
  for (const f of frames) {
    if (f.pitchHz !== null && pitchMedian) f.relativePitch = 12 * Math.log2(f.pitchHz / pitchMedian);
    if (f.active && levelMedian !== null) f.relativeDb = f.rmsDb - levelMedian;
  }
  const voicedFrames = frames.filter(f => f.pitchHz !== null).length;
  const voicedDuration = Math.min(duration, voicedFrames * hopSize / rate);
  return { frames, duration, recordingDuration: duration, voicedDuration, excludedDuration: Math.max(0, duration - voicedDuration),
    sampleRate, pitchMedian, levelMedian, noiseFloor,
    voicedFraction: frames.length ? voicedFrames / frames.length : 0, voicedFrames, activeFloor };
}

function frameCost(a, b) {
  let cost = 0, used = 0;
  if (a.relativePitch !== null && b.relativePitch !== null) {
    cost += Math.min(8, Math.abs(a.relativePitch - b.relativePitch)) / 4;
    used++;
  } else if ((a.relativePitch === null) !== (b.relativePitch === null)) {
    cost += 0.8;
    used++;
  }
  if (a.relativeDb !== null && b.relativeDb !== null) {
    cost += 0.25 * Math.min(18, Math.abs(a.relativeDb - b.relativeDb)) / 6;
    used++;
  }
  return used ? cost : 0.25;
}

/** Constrained DTW is used only for approximate comparisons; the path does not
 * identify words or syllables. Reference and user recordings should contain the
 * same selected phrase. Sequence duration and silence are not diagnosed. */
export function compareAnalyses(reference, user) {
  if (!reference?.frames || !user?.frames) throw new TypeError('Two analysis results are required.');
  const warnings = [];
  function voicedSequence(frames) {
    const indices = [];
    for (let i = 0; i < frames.length; i++) {
      if (frames[i].active && Number.isFinite(frames[i].relativePitch) && Number.isFinite(frames[i].relativeDb)) indices.push(i);
    }
    return { indices, frames: indices.map(i => frames[i]) };
  }
  // Compare only reliable voice, skipping every gap including internal pauses.
  // Keep original indices so charts and replay still address the original clip.
  const r = voicedSequence(reference.frames), u = voicedSequence(user.frames);
  const n = r.frames.length, m = u.frames.length;
  if (n < 8 || m < 8 || !reference.pitchMedian || !user.pitchMedian) {
    return { path: [], pitchError: null, intensityError: null, voicedPairs: 0, durationRatio: null,
      warnings: ['음높이를 충분히 확인하지 못했어요. 조용한 곳에서 다시 녹음해 주세요.'] };
  }
  // Band limits extreme warping. The original times remain in the frames.
  const cols = m + 1;
  const costs = new Float64Array((n + 1) * cols);
  costs.fill(Infinity);
  costs[0] = 0;
  const steps = new Uint8Array((n + 1) * cols);
  const band = Math.max(8, Math.ceil(Math.max(n, m) * 0.2));
  for (let i = 1; i <= n; i++) {
    const center = i * m / n;
    const from = Math.max(1, Math.floor(center - band));
    const to = Math.min(m, Math.ceil(center + band));
    for (let j = from; j <= to; j++) {
      const at = i * cols + j;
      const diagonal = costs[(i - 1) * cols + j - 1];
      const vertical = costs[(i - 1) * cols + j] + 0.18;
      const horizontal = costs[i * cols + j - 1] + 0.18;
      let best = diagonal, step = 1;
      if (vertical < best) { best = vertical; step = 2; }
      if (horizontal < best) { best = horizontal; step = 3; }
      if (Number.isFinite(best)) { costs[at] = best + frameCost(r.frames[i - 1], u.frames[j - 1]); steps[at] = step; }
    }
  }
  if (!Number.isFinite(costs[n * cols + m])) {
    return { path: [], pitchError: null, intensityError: null, voicedPairs: 0, durationRatio: null,
      warnings: ['두 녹음의 길이가 많이 달라 비교하기 어려워요.'] };
  }
  let i = n, j = m;
  const path = [];
  while (i > 0 && j > 0) {
    path.push([r.indices[i - 1], u.indices[j - 1]]);
    const step = steps[i * cols + j];
    if (step === 1) { i--; j--; }
    else if (step === 2) i--;
    else if (step === 3) j--;
    else break;
  }
  path.reverse();
  const pitches = [], levels = [];
  for (const [ri, ui] of path) {
    const a = reference.frames[ri], b = user.frames[ui];
    if (a.relativePitch !== null && b.relativePitch !== null) pitches.push([ri, ui, Math.abs(a.relativePitch - b.relativePitch)]);
    if (a.relativeDb !== null && b.relativeDb !== null) levels.push([ri, ui, Math.abs(a.relativeDb - b.relativeDb)]);
  }
  if (pitches.length < 8 || pitches.length / path.length < 0.2) warnings.push('비교 가능한 높낮이 구간이 적어 결과가 불안정할 수 있어요.');
  // Each recording's frames contribute equally, instead of allowing DTW's
  // repeated matches to erase a difference in half of a phrase.
  function symmetricMean(pairs) {
    if (!pairs.length) return null;
    function side(index) {
      const perFrame = new Map();
      for (const pair of pairs) {
        const key = pair[index], state = perFrame.get(key) || [0, 0];
        state[0] += pair[2]; state[1]++;
        perFrame.set(key, state);
      }
      let total = 0;
      for (const [sum, count] of perFrame.values()) total += sum / count;
      return total / perFrame.size;
    }
    return (side(0) + side(1)) / 2;
  }
  return { path, pitchError: pitches.length >= 8 ? symmetricMean(pitches) : null,
    intensityError: levels.length ? symmetricMean(levels) : null, voicedPairs: pitches.length,
    durationRatio: m / n, warnings };
}
