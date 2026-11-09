import createRNNWasmModule from './vendor/rnnoise/rnnoise.mjs';
import { LevelMeter } from './level-meter.mjs';

const frameSize = 480;
const pcmScale = 32768;

/** Continuous denoised PCM. VAD describes frames; it never removes samples. */
export async function createNoiseProcessor(wasmBinary, vad, sampleRate = 48000) {
  if (sampleRate !== 48000) throw new RangeError('RNNoise requires 48000 Hz');
  const engine = await createRNNWasmModule({ wasmBinary });
  let state = 0, buffer = 0, used = 0, previous = null, disposed = false, finished = false;
  try {
    state = engine._rnnoise_create(0);
    buffer = engine._malloc(frameSize * 2 * Float32Array.BYTES_PER_ELEMENT);
    if (!state || !buffer) throw new Error('RNNoise allocation failed');
  } catch (error) {
    if (state) engine._rnnoise_destroy(state);
    if (buffer) engine._free(buffer);
    throw error;
  }
  const offset = buffer / 4;
  const pending = new Float32Array(frameSize);
  function process(length) {
    for (let i = 0; i < frameSize; i++) engine.HEAPF32[offset + i] = pending[i] * pcmScale;
    const score = engine._rnnoise_process_frame(state, buffer + frameSize * 4, buffer);
    if (!Number.isFinite(score)) throw new Error('RNNoise returned an invalid score');
    let result;
    if (previous) {
      const output = new Float32Array(frameSize);
      for (let i = 0; i < frameSize; i++) {
        output[i] = engine.HEAPF32[offset + frameSize + i] / pcmScale;
        if (!Number.isFinite(output[i])) throw new Error('RNNoise returned invalid PCM');
      }
      const detected = vad.process(output);
      if (typeof detected !== 'boolean') throw new Error('VAD returned an invalid decision');
      // The zero frame only drains latency: its score is not real speech evidence.
      const supported = length === 0 ? previous.score : Math.min(previous.score, score);
      const quiet = length === 0 ? previous.score : Math.max(previous.score, score);
      const speech = detected && supported >= .5 ? 'speech' : (!detected && quiet < .2 ? 'nonSpeech' : 'uncertain');
      // RNNoise can overshoot full scale even when microphone PCM is bounded.
      for (let i = 0; i < output.length; i++) output[i] = Math.max(-1, Math.min(1, output[i]));
      result = { samples: output.slice(0, previous.length), speech };
    }
    previous = length ? { length, score } : null;
    pending.fill(0); used = 0;
    return result;
  }
  return {
    push(samples) {
      if (disposed || finished) throw new Error('Noise processor is finished or disposed');
      const frames = [];
      for (const sample of samples) {
        if (!Number.isFinite(sample)) throw new RangeError('Samples must be finite');
        pending[used++] = sample;
        if (used === frameSize) { const frame = process(frameSize); if (frame) frames.push(frame); }
      }
      return frames;
    },
    finish() {
      if (disposed) throw new Error('Noise processor is disposed');
      if (finished) return [];
      finished = true;
      const frames = [];
      if (used) { const frame = process(used); if (frame) frames.push(frame); }
      if (previous) { const frame = process(0); if (frame) frames.push(frame); }
      return frames;
    },
    dispose() {
      if (disposed) return;
      disposed = true;
      vad?.dispose(); pending.fill(0);
      engine.HEAPF32.fill(0, offset, offset + frameSize * 2);
      engine._rnnoise_destroy(state); engine._free(buffer);
      previous = null;
    },
  };
}

/** RNNoise accepts 10 ms of 48 kHz PCM16-scaled floats, not Web Audio floats. */
export async function createNoiseMeter(wasmBinary, sampleRate = 48000, analysis = null) {
  if (sampleRate !== 48000) throw new RangeError('RNNoise requires 48000 Hz');
  const engine = await createRNNWasmModule({wasmBinary});
  let state = 0, buffer = 0;
  try {
    state = engine._rnnoise_create(0);
    buffer = engine._malloc(frameSize * 2 * Float32Array.BYTES_PER_ELEMENT);
    if (!state || !buffer) throw new Error('RNNoise allocation failed');
  } catch (error) {
    if (state) engine._rnnoise_destroy(state);
    if (buffer) engine._free(buffer);
    throw error;
  }
  const inputOffset = buffer / Float32Array.BYTES_PER_ELEMENT;
  const outputOffset = inputOffset + frameSize;
  const output = new Float32Array(frameSize);
  let meter = new LevelMeter(sampleRate);
  let count = 0, disposed = false, energy = 0, peak = 0, sequence = 0, previous = null;
  return {
    reset() {
      if (disposed) throw new Error('Noise meter is disposed');
      const next = engine._rnnoise_create(0);
      if (!next) throw new Error('RNNoise reset failed');
      engine._rnnoise_destroy(state); state = next;
      analysis?.vad?.reset();
      engine.HEAPF32.fill(0, inputOffset, outputOffset + frameSize);
      output.fill(0); meter = new LevelMeter(sampleRate);
      count = energy = peak = sequence = 0; previous = null;
    },
    push(samples) {
      if (disposed) throw new Error('Noise meter is disposed');
      const levels = [];
      for (const sample of samples) {
        if (!Number.isFinite(sample)) throw new RangeError('Samples must be finite');
        energy += sample * sample;
        peak = Math.max(peak, Math.abs(sample));
        engine.HEAPF32[inputOffset + count++] = sample * pcmScale;
        if (count !== frameSize) continue;
        const score = engine._rnnoise_process_frame(state, buffer + frameSize * 4, buffer);
        // Read the current heap: a WASM memory growth can replace HEAPF32.
        for (let i=0; i<frameSize; i++) output[i] = engine.HEAPF32[outputOffset+i] / pcmScale;
        if (analysis?.vad) {
          try {
            const speech = analysis.vad.process(output);
            let processedEnergy = 0;
            for (const sample of output) processedEnergy += sample * sample;
            // libfvad hangover can outlive an impulse; require independent model support.
            // Keep both adjacent scores because RNNoise output is delayed one frame.
            // A rejected VAD positive is disagreement, not evidence of quiet background.
            if (previous) analysis.onAnalysis({...previous, meterRms:Math.sqrt(processedEnergy/frameSize), speech: speech && score >= .5 && previous.score >= .5 ? 'speech' : (!speech && score < .2 && previous.score < .2 ? 'nonSpeech' : 'uncertain')});
          } catch {
            analysis.vad.dispose?.(); analysis.vad = null; analysis.onFailure?.();
          }
        }
        previous = {seq:sequence, sampleStart:sequence*frameSize, sampleEnd:(sequence+1)*frameSize, power:energy/frameSize, clipped:peak >= .999, score};
        sequence++; energy = peak = 0;
        levels.push(...meter.push(output));
        count = 0;
      }
      return levels;
    },
    dispose() {
      if (disposed) return;
      disposed = true;
      analysis?.vad?.dispose?.();
      output.fill(0);
      engine.HEAPF32.fill(0, inputOffset, outputOffset + frameSize);
      engine._rnnoise_destroy(state);
      engine._free(buffer);
    },
  };
}
