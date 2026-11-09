import {createNoiseProcessor} from './noise-reducer.mjs';

/** Default capture keeps RNNoise; pronunciation preserves raw PCM without detectors. */
export async function createCaptureProcessor(wasmBinary, vad, sampleRate = 48000, noiseReductionEnabled = true) {
  if (noiseReductionEnabled) {
    return createNoiseProcessor(wasmBinary, vad, sampleRate);
  }
  if (sampleRate !== 48000) throw new RangeError('Capture requires 48000 Hz');
  const pending = new Float32Array(480);
  let used = 0, disposed = false, finished = false;
  function frame(length) {
    const speech = vad ? vad.process(pending) : null;
    if (vad && typeof speech !== 'boolean') throw new Error('VAD returned an invalid decision');
    const result = {samples: pending.slice(0, length), speech: speech === null ? null : speech ? 'speech' : 'nonSpeech'};
    pending.fill(0); used = 0;
    return result;
  }
  return {
    push(samples) {
      if (disposed || finished) throw new Error('Capture processor is finished or disposed');
      const frames = [];
      for (const sample of samples) {
        if (!Number.isFinite(sample)) throw new RangeError('Samples must be finite');
        pending[used++] = sample;
        if (used === 480) frames.push(frame(480));
      }
      return frames;
    },
    finish() {
      if (disposed) throw new Error('Capture processor is disposed');
      if (finished) return [];
      finished = true;
      return used ? [frame(used)] : [];
    },
    dispose() {
      if (disposed) return;
      disposed = true; pending.fill(0); vad?.dispose();
    },
  };
}
