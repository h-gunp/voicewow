import { createNoiseProcessor } from './noise-reducer.mjs';
import { createVoiceActivity } from './voice-activity.mjs';

// Muted output keeps the graph running; continuous clean PCM travels over the port.
class ProcessedCapture extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this.frames = this.emitted = this.used = this.sequence = 0;
    this.sum = this.sumSquares = 0;
    this.stopped = false;
    this.hasInput = false;
    this.buffer = new Float32Array(4800);
    this.speech = {speechFrames: 0, nonSpeechFrames: 0, uncertainFrames: 0, totalFrames: 0};
    const {wasmBinary, vadBinary, maxSeconds = 10} = options.processorOptions;
    this.maxFrames = Math.floor(sampleRate * maxSeconds);
    this.port.onmessage = ({data}) => {
      if (data?.type === 'cancel' || data?.type === 'dispose') { this.dispose(); return; }
      if (this.stopped) return;
      if (data?.type === 'finish') this.finish(false);
      else this.fail('Invalid recording command');
    };
    this.prepare(wasmBinary, vadBinary);
  }

  async prepare(wasmBinary, vadBinary) {
    let vad;
    try {
      if (sampleRate !== 48000 || !Number.isFinite(this.maxFrames) || this.maxFrames < 1 || this.maxFrames > 960000) throw new Error('Unsupported processed capture settings');
      vad = await createVoiceActivity(vadBinary);
      if (this.stopped) { vad.dispose(); return; }
      const processor = await createNoiseProcessor(wasmBinary, vad, sampleRate);
      if (this.stopped) { processor.dispose(); return; }
      this.processor = processor;
      this.port.postMessage({type: 'ready', vadStatus: 'ready'});
    } catch (error) { vad?.dispose(); if (!this.stopped) this.fail(error.message); }
  }

  dispose() {
    this.stopped = true;
    this.processor?.dispose(); this.processor = null;
    this.buffer = null;
  }

  fail(reason) {
    this.dispose();
    this.port.postMessage({type: 'error', reason});
    return false;
  }

  flush() {
    if (!this.used) return;
    const samples = this.buffer.slice(0, this.used);
    this.port.postMessage({type: 'pcm', samples, sampleRate, sequence: ++this.sequence,
      startFrame: this.emitted, speech: {...this.speech}}, [samples.buffer]);
    this.emitted += this.used; this.used = 0;
  }

  collect(frames) {
    for (const frame of frames) {
      this.speech[`${frame.speech}Frames`]++;
      this.speech.totalFrames++;
      for (const sample of frame.samples) {
        this.buffer[this.used++] = sample;
        if (this.used === this.buffer.length) this.flush();
      }
    }
  }

  finish(limit) {
    if (this.stopped) return;
    try {
      if (!this.processor) throw new Error('Capture processor is not ready');
      this.collect(this.processor.finish());
      this.flush();
      if (this.emitted !== this.frames) throw new Error('Processed PCM length mismatch');
      const rawVariance = this.frames ? Math.max(0, this.sumSquares / this.frames - (this.sum / this.frames) ** 2) : 0;
      this.dispose();
      if (limit) this.port.postMessage({type: 'limit'});
      this.port.postMessage({type: 'finished', sequence: this.sequence, frames: this.frames,
        speech: {...this.speech}, rawVariance});
    } catch (error) { this.fail(error.message); }
  }

  process(inputs, outputs) {
    for (const output of outputs) for (const channel of output) channel.fill(0);
    if (this.stopped) return false;
    if (!this.processor) return true;
    const channels = inputs[0];
    if (!channels?.length) return this.hasInput ? this.fail('Audio input interrupted') : true;
    this.hasInput = true;
    const length = Math.min(channels[0].length, this.maxFrames - this.frames);
    if (channels.some(channel => channel.length !== channels[0].length)) return this.fail('Invalid channel lengths');
    const mono = new Float32Array(length);
    for (let i = 0; i < length; i++) {
      for (const channel of channels) mono[i] += channel[i] / channels.length;
      if (!Number.isFinite(mono[i])) return this.fail('Non-finite audio input');
      this.sum += mono[i]; this.sumSquares += mono[i] * mono[i];
    }
    this.frames += length;
    try { this.collect(this.processor.push(mono)); }
    catch (error) { return this.fail(error.message); }
    if (this.frames === this.maxFrames) { this.finish(true); return false; }
    return true;
  }
}
registerProcessor('voicemate-processed-capture', ProcessedCapture);
