import createRNNWasmModule from './vendor/rnnoise/rnnoise.mjs';
import { LevelMeter } from './level-meter.mjs';

const frameSize = 480;
const pcmScale = 32768;

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
            if (previous) analysis.onAnalysis({...previous, meterRms:Math.sqrt(processedEnergy/frameSize), speech: speech ? 'speech' : (score < .2 && previous.score < .2 ? 'nonSpeech' : 'uncertain')});
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
