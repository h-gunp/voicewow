import { createNoiseMeter } from './noise-reducer.mjs';
import { createVoiceActivity } from './voice-activity.mjs';

class NoiseMeterProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this.finished = false;
    this.meter = null;
    this.port.onmessage = ({data}) => { if (data?.type === 'dispose') this.dispose(); };
    const {wasmBinary, vadBinary} = options.processorOptions;
    let vadStatus = vadBinary ? 'init_failed' : 'load_failed';
    const prepareVad = vadBinary ? createVoiceActivity(vadBinary).catch(() => null) : Promise.resolve(null);
    prepareVad.then(async vad => {
      if (vad) vadStatus = 'ready';
      try {
        return await createNoiseMeter(wasmBinary, sampleRate, vad ? {
          vad,
          onAnalysis: frame => this.port.postMessage({type:'analysis', ...frame, sampleTime:this.origin + frame.sampleEnd/sampleRate}),
          onFailure: () => this.port.postMessage({type:'analysis_unavailable'}),
        } : null);
      } catch (error) { vad?.dispose(); throw error; }
    }).then(meter => {
      if (this.finished) { meter.dispose(); return; }
      this.meter = meter;
      this.port.postMessage({type:'ready',vadStatus});
    }).catch(() => {
      if (this.finished) return;
      this.dispose();
      this.port.postMessage({type:'error'});
    });
  }
  dispose() {
    this.finished = true;
    this.meter?.dispose();
    this.meter = null;
  }
  process(inputs) {
    if (this.finished) return false;
    const input = inputs[0]?.[0];
    if (!this.meter) return true;
    if (!input || input.length === 0) {
      if (this.origin !== undefined && !this.gap) {
        this.gap = true;
        this.port.postMessage({type:'analysis_reset'});
      }
      return true;
    }
    try {
      if (this.gap) { this.meter.reset(); this.origin = undefined; this.gap = false; }
      if (this.origin === undefined) this.origin = (globalThis.currentFrame ?? 0) / sampleRate;
      for (const frame of this.meter.push(input)) this.port.postMessage({type:'level', ...frame});
    } catch {
      this.dispose();
      this.port.postMessage({type:'error'});
      return false;
    }
    return true;
  }
}
registerProcessor('voicemate-noise-meter', NoiseMeterProcessor);
