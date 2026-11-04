// A time-based recording view, never live speech/text alignment or a verdict.
// Relative baselines use the voice observed so far and remain provisional until
// the complete recording is analysed. Missing measurements stay missing.
const PITCH_FLOOR = 5;
const LEVEL_FLOOR = 10;
const HEADROOM = 1.12;

function median(values) {
  const sorted = values.filter(Number.isFinite).sort((a, b) => a - b);
  if (!sorted.length) return null;
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

function isVoice(frame) {
  return frame?.active !== false && Number.isFinite(frame?.pitchHz) && frame.pitchHz > 0;
}

function supportedBound(frames, field, minimum) {
  let bound = minimum;
  for (const frame of frames) {
    const value = frame[field];
    if (Number.isFinite(value)) bound = Math.max(bound, Math.ceil(Math.abs(value) * HEADROOM));
  }
  return bound;
}

/** One instance belongs to one recording. A reference analysis is preferred;
 * a numeric reference duration is also accepted when no reference values exist.
 * Domain expands in whole initial spans instead of rescaling on every sample.
 * Vertical bounds may expand to keep measurements visible, but never shrink.
 */
export function createLiveView(reference = null) {
  const duration = typeof reference === 'number' ? reference : reference?.duration;
  const referenceFrames = Array.isArray(reference?.frames) ? reference.frames : [];
  const baseDomain = Math.max(Number.isFinite(duration) && duration > 0 ? duration * 1.1 : 0, 1.5);
  let domainSeconds = baseDomain;
  let pitchBound = supportedBound(referenceFrames, 'relativePitch', PITCH_FLOOR);
  let levelBound = supportedBound(referenceFrames, 'relativeDb', LEVEL_FLOOR);

  return {
    update(frames = [], elapsedFromFirstVoice = 0) {
      // Invalid timestamps cannot be placed without inventing their location.
      // Valid isolated samples, null gaps and their chronological order remain.
      const observations = (Array.isArray(frames) ? frames : [])
        .filter(frame => Number.isFinite(frame?.time) && frame.time >= 0)
        .slice().sort((a, b) => a.time - b.time);
      const voiced = observations.filter(isVoice);
      const pitchMedian = median(voiced.map(frame => frame.pitchHz));
      const levelMedian = median(voiced.map(frame => frame.rmsDb));
      const trace = observations.map(frame => {
        const voice = isVoice(frame);
        const relativePitch = voice && pitchMedian !== null ? 12 * Math.log2(frame.pitchHz / pitchMedian) : null;
        const relativeDb = voice && Number.isFinite(frame.rmsDb) && levelMedian !== null ? frame.rmsDb - levelMedian : null;
        return {
          time: frame.time,
          relativePitch: Number.isFinite(relativePitch) ? relativePitch : null,
          relativeDb: Number.isFinite(relativeDb) ? relativeDb : null,
        };
      });
      const elapsed = Number.isFinite(elapsedFromFirstVoice) ? Math.max(0, elapsedFromFirstVoice) : 0;
      const latestTime = Math.max(elapsed, trace.at(-1)?.time || 0);
      if (latestTime > domainSeconds) domainSeconds = Math.ceil(latestTime / baseDomain) * baseDomain;
      pitchBound = Math.max(pitchBound, supportedBound(trace, 'relativePitch', PITCH_FLOOR));
      levelBound = Math.max(levelBound, supportedBound(trace, 'relativeDb', LEVEL_FLOOR));
      return {
        trace, domainSeconds, pitchBound, levelBound,
        voicedFrames: voiced.length,
        hasCurrentVoice: observations.length > 0 && isVoice(observations.at(-1)),
      };
    },
  };
}
