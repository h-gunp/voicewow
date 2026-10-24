/** 100 ms RMS/peak windows. No audio samples are retained after push returns. */
export class LevelMeter {
  constructor(sampleRate, windowMs = 100) {
    if (!Number.isFinite(sampleRate) || sampleRate <= 0 || !Number.isFinite(windowMs) || windowMs <= 0) throw new RangeError('Positive finite sample rate and window required');
    this.windowSize = Math.round(sampleRate * windowMs / 1000);
    if (this.windowSize < 1) throw new RangeError('Window must contain samples');
    this.count = 0; this.energy = 0; this.peak = 0;
  }
  push(samples) {
    const frames = [];
    for (const sample of samples) {
      if (!Number.isFinite(sample)) throw new RangeError('Samples must be finite');
      this.energy += sample * sample;
      this.peak = Math.max(this.peak, Math.abs(sample));
      if (++this.count === this.windowSize) {
        const rms = Math.sqrt(this.energy / this.count);
        const dbfs = rms === 0 ? null : 20 * Math.log10(rms);
        frames.push({ rms, peak: this.peak, dbfs, normalized: dbfs === null ? 0 : Math.max(0, Math.min(1, (dbfs + 80) / 80)), sampleCount: this.count });
        this.count = 0; this.energy = 0; this.peak = 0;
      }
    }
    return frames;
  }
}
