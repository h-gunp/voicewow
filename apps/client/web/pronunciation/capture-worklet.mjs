// Bounded mono PCM capture; final acknowledgment follows the last partial chunk.
class PronunciationCapture extends AudioWorkletProcessor {
  constructor() {
    super();
    this.chunkFrames = Math.round(sampleRate / 10);
    this.maxFrames = Math.floor(sampleRate * 10);
    this.buffer = new Float32Array(this.chunkFrames);
    this.used = 0;
    this.frames = 0;
    this.sequence = 0;
    this.stopped = false;
    this.hasInput = false;
    this.port.onmessage = ({ data }) => {
      if (this.stopped) return;
      if (data?.type === 'finish') this.finish(false);
      else if (data?.type === 'cancel') { this.stopped = true; this.buffer = null; }
      else this.fail('Invalid recording command');
    };
  }

  flush() {
    if (!this.used) return;
    const samples = this.buffer.slice(0, this.used);
    this.port.postMessage({ type: 'pcm', samples, sampleRate,
      sequence: ++this.sequence, startFrame: this.frames - this.used }, [samples.buffer]);
    this.used = 0;
  }

  finish(limit) {
    this.flush();
    this.stopped = true;
    this.buffer = null;
    if (limit) this.port.postMessage({ type: 'limit' });
    this.port.postMessage({ type: 'finished', sequence: this.sequence, frames: this.frames });
  }

  fail(reason) {
    this.stopped = true;
    this.buffer = null;
    this.port.postMessage({ type: 'error', reason });
    return false;
  }

  process(inputs, outputs) {
    for (const output of outputs) for (const channel of output) channel.fill(0);
    if (this.stopped) return false;
    const channels = inputs[0];
    if (!channels?.length) return this.hasInput ? this.fail('Audio input interrupted') : true;
    this.hasInput = true;
    const frames = channels[0].length;
    if (channels.some(channel => channel.length !== frames)) return this.fail('Invalid channel lengths');
    for (let frame = 0; frame < frames; frame++) {
      let mono = 0;
      for (const channel of channels) mono += channel[frame] / channels.length;
      if (!Number.isFinite(mono)) return this.fail('Non-finite audio input');
      this.buffer[this.used++] = mono;
      this.frames++;
      if (this.used === this.chunkFrames) this.flush();
      if (this.frames === this.maxFrames) { this.finish(true); return false; }
    }
    return true;
  }
}

registerProcessor('pronunciation-capture', PronunciationCapture);
