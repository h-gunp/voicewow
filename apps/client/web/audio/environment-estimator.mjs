// All thresholds below are experimental; samples are contiguous 10 ms frames.
const db = p => 10 * Math.log10(p);
const median = a => { const s = [...a].sort((x,y)=>x-y); return s[Math.floor(s.length/2)]; };

export class EnvironmentEstimator {
  constructor() {
    this.seq = -1; this.pending = []; this.noise = []; this.lastEvidence = -Infinity;
    this.initial = null; this.smooth = null; this.offset = 0; this.candidate = null;
    this.post = 0; this.voice = null; this.state = 'collecting';
    this.evidenceSinceStats = 0;
    this.transition = false;
  }
  hold() {
    this.pending = []; this.noise = []; this.smooth = null; this.candidate = null;
    this.evidenceSinceStats = 0; this.post = 50; this.voice = null; this.state = 'held'; this.transition = false;
  }
  add(frame) {
    const {seq,power,speech,clipped} = frame;
    if (!Number.isSafeInteger(seq) || seq <= this.seq) return;
    if (!Number.isFinite(power) || power < 0 || !['speech','nonSpeech','uncertain'].includes(speech)) throw new RangeError('invalid analysis frame');
    if (this.seq >= 0 && seq !== this.seq + 1) {
      this.pending = []; this.noise = []; this.smooth = null; this.candidate = null;
      this.state = 'held'; this.post = 50; this.transition = false;
    }
    this.seq = seq;
    this.speech = clipped ? 'uncertain' : speech;
    if (speech !== 'nonSpeech' || clipped) {
      this.pending = []; this.post = 50;
    } else if (this.post > 0) {
      this.post--;
    } else if (seq >= 50) {
      this.pending.push(frame);
      if (this.pending.length > 20) this.accept(this.pending.shift());
    }
    if (seq - this.lastEvidence > 500 && this.initial !== null) {
      this.state = 'held'; this.noise = []; this.smooth = null; this.candidate = null; this.transition = false;
    }
    this.voice = null;
    if (speech === 'speech' && !clipped && this.state === 'ready' && this.smooth > 0) {
      const voice = power - this.smooth;
      if (voice > 0 && voice / this.smooth >= 2) this.voice = db(voice);
    }
  }
  accept(frame) {
    this.lastEvidence = frame.seq;
    this.noise.push(frame);
    this.evidenceSinceStats++;
    this.noise = this.noise.filter(x=>frame.seq-x.seq<1000);
    if (this.noise.length < 300 || frame.seq % 10 !== 0) return;
    const fresh = this.evidenceSinceStats;
    this.evidenceSinceStats = 0;
    const values = this.noise.map(x=>x.power).sort((a,b)=>a-b);
    const q1 = values[Math.floor(values.length*.25)], q3 = values[Math.floor(values.length*.75)];
    if (q1 <= 0 || db(q3/q1) > 3) { this.state = 'held'; this.candidate = null; this.transition = false; return; }
    const value = median(values);
    this.smooth = this.smooth === null ? value : this.smooth + (1-Math.exp(-.1/2))*(value-this.smooth);
    if (this.initial === null) this.initial = this.smooth;
    this.state = 'ready';
    const change = db(this.smooth/this.initial), desired = Math.max(0, change*.5);
    if (desired > 3) { this.state = 'unsupported'; this.candidate = null; return; }
    // Return to the baseline in steps even when one step is smaller than entry hysteresis.
    const target = desired <= .75 ? 0 : desired;
    const difference = target-this.offset;
    if (Math.abs(difference) <= .75 && !(target === 0 && this.offset > 0)) { this.candidate = null; this.transition = false; return; }
    if (difference > 0 && difference < 1.5 && !this.transition) return;
    const direction = Math.sign(difference);
    if (!this.candidate || this.candidate.direction !== direction || frame.seq-this.candidate.last > 200) {
      this.candidate = {direction,start:frame.seq,last:frame.seq,count:1};
    } else {
      this.candidate.count += Math.min(fresh, 10);
    }
    this.candidate.last = frame.seq;
    if (this.candidate.count >= 300 && frame.seq-this.candidate.start >= 500) {
      this.offset = Math.max(0,Math.min(3,this.offset + direction*Math.min(1,Math.abs(difference))));
      this.transition = true;
      this.candidate = null;
    }
  }
  snapshot() { return {state:this.state, speech:this.speech, noiseDbfs:this.state === 'ready' && this.smooth > 0 ? db(this.smooth) : null, voiceDbfs:this.voice, offset:this.state === 'ready' ? this.offset : null}; }
}
