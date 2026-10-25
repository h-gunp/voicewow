import { createNoiseMeter } from './noise-reducer.mjs';

class NoiseMeterProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this.finished = false;
    this.meter = null;
    this.port.onmessage = ({data}) => { if (data?.type === 'dispose') this.dispose(); };
    createNoiseMeter(options.processorOptions.wasmBinary, sampleRate).then(meter => {
      if (this.finished) { meter.dispose(); return; }
      this.meter = meter;
      this.port.postMessage({type:'ready'});
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
    if (!this.meter || !input) return true;
    try {
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
