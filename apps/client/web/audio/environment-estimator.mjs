// Experimental sampling thresholds; each accepted frame contains disjoint 10 ms input.
const db = power => 10 * Math.log10(power);

export class EnvironmentEstimator {
  constructor() {
    this.seq = -1; this.speech = undefined; this.result = null;
    this.state = 'idle'; this.reason = null; this.count = 0; this.clipped = 0; this.powers = [];
  }
  sample() {
    if (this.state === 'collecting') return;
    this.state = 'collecting'; this.reason = null;
    this.count = 0; this.clipped = 0; this.powers = [];
  }
  cancel() {
    if (this.state !== 'collecting') return;
    this.state = this.result ? 'ready' : 'idle'; this.reason = null;
    this.count = 0; this.clipped = 0; this.powers = [];
  }
  hold(reason = 'input_gap', state = 'failed') {
    this.result = null; this.state = state; this.reason = reason;
    this.count = 0; this.clipped = 0; this.powers = [];
  }
  resetEpoch() {
    this.hold(); this.seq = -1; this.speech = undefined;
  }
  add({seq,power,speech,clipped}, collect = true) {
    if (!Number.isSafeInteger(seq) || seq < 0) throw new RangeError('invalid analysis frame');
    if (seq <= this.seq) return;
    if (!Number.isFinite(power) || power < 0 || !['speech','nonSpeech','uncertain'].includes(speech) || typeof clipped !== 'boolean') throw new RangeError('invalid analysis frame');
    if (this.seq >= 0 && seq !== this.seq + 1) this.hold();
    this.seq = seq; this.speech = clipped ? 'uncertain' : speech;
    if (this.state !== 'collecting' || !collect) return;
    this.count++;
    if (clipped) this.clipped++;
    else if (power > 0) this.powers.push(power);
    if (this.count < 500) return;
    this.powers.sort((a,b)=>a-b);
    const n = this.powers.length;
    if (this.clipped >= 50) this.reason = 'clipping';
    else if (n < 400) this.reason = 'insufficient_samples';
    else if (db(this.powers[Math.floor(n*.75)]/this.powers[Math.floor(n*.25)]) > 12 + 1e-9) this.reason = 'unstable_environment';
    else {
      const lower = this.powers[Math.floor((n-1)/2)], upper = this.powers[Math.floor(n/2)];
      const power = lower + (upper-lower)/2;
      const noiseDbfs = db(power);
      this.result = {noiseDbfs, offset:Math.round(Math.min(3,Math.max(0,(noiseDbfs+60)/10))*10)/10};
    }
    this.state = this.reason ? 'failed' : 'ready';
    this.powers = [];
  }
  snapshot() {
    return {state:this.state,calibrationValid:this.result !== null,progress:this.count/500,noiseDbfs:this.result?.noiseDbfs ?? null,offset:this.result?.offset ?? null,reason:this.reason,speech:this.speech,voiceDbfs:null};
  }
}
