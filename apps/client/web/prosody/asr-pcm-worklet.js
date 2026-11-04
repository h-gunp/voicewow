// Bounded PCM transport. No recognition, network, resampling or track ownership.
class VoiceMateAsrPcmProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this.chunkFrames = options?.processorOptions?.chunkFrames;
    this.maxInFlight = options?.processorOptions?.maxInFlight;
    if (!Number.isInteger(this.chunkFrames) || this.chunkFrames < 80 || this.chunkFrames > 19200
      || !Number.isInteger(this.maxInFlight) || this.maxInFlight < 1 || this.maxInFlight > 4) {
      throw new Error('Invalid PCM transport bounds');
    }
    this.buffer = new Float32Array(this.chunkFrames);
    this.used = 0; this.sequence = 0; this.startFrame = 0; this.stopped = false; this.hasInput = false;
    this.pending = new Set();
    this.port.onmessage = event => {
      if (this.stopped) return;
      const message = event.data;
      if (message?.type === 'stop') { this.stopped = true; this.pending.clear(); return; }
      if (message?.type !== 'ack' || !this.pending.delete(message.sequence)) this.fail('invalid acknowledgment');
    };
  }
  fail(reason) {
    if (this.stopped) return;
    this.stopped = true; this.pending.clear(); this.used = 0;
    this.port.postMessage({ type: 'error', reason });
  }
  process(inputs, outputs) {
    for (const output of outputs) for (const channel of output) channel.fill(0);
    if (this.stopped) return false;
    const channels = inputs[0];
    if (!channels?.length) {
      if (this.hasInput) { this.fail('audio input interrupted'); return false; }
      return true;
    }
    this.hasInput = true;
    const frames = channels[0].length;
    if (channels.some(channel => channel.length !== frames)) { this.fail('invalid channel lengths'); return false; }
    for (let i = 0; i < frames; i++) {
      let mono = 0;
      for (const channel of channels) mono += channel[i] / channels.length;
      if (!Number.isFinite(mono)) { this.fail('non-finite audio'); return false; }
      this.buffer[this.used++] = mono;
      if (this.used === this.chunkFrames) {
        if (this.pending.size >= this.maxInFlight) { this.fail('consumer too slow; audio continuity lost'); return false; }
        const sequence = ++this.sequence;
        this.pending.add(sequence);
        this.port.postMessage({ type: 'pcm', samples: this.buffer, sampleRate,
          sequence, startFrame: this.startFrame }, [this.buffer.buffer]);
        this.startFrame += this.chunkFrames;
        this.buffer = new Float32Array(this.chunkFrames); this.used = 0;
      }
    }
    return true;
  }
}
registerProcessor('voicemate-asr-pcm', VoiceMateAsrPcmProcessor);
