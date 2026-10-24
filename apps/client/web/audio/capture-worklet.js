import { LevelMeter } from './level-meter.mjs';

class VoiceMateProcessor extends AudioWorkletProcessor {
  constructor() { super(); this.meter = new LevelMeter(sampleRate); this.failed = false; }
  process(inputs) {
    if (this.failed) return false;
    const input = inputs[0]?.[0];
    if (!input) return true;
    try {
      for (const frame of this.meter.push(input)) this.port.postMessage({type:'level', ...frame});
    } catch {
      this.failed = true; this.port.postMessage({type:'error'}); return false;
    }
    return true;
  }
}
registerProcessor('voicemate-meter', VoiceMateProcessor);
