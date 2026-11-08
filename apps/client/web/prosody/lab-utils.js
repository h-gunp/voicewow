export function median(values) {
  const a = values.filter(Number.isFinite).sort((x,y) => x-y);
  if (!a.length) return null;
  const m = Math.floor(a.length / 2);
  return a.length % 2 ? a[m] : (a[m-1] + a[m]) / 2;
}

export function alignedTrace(reference, user, path) {
  const buckets = reference.frames.map(() => []), breaks = new Set(), ambiguous = new Set();
  let previous = null;
  for (const [r,u] of path) {
    if (previous && u > previous[1] + 1) {
      if (r === previous[0]) ambiguous.add(r);
      else breaks.add(r);
    }
    buckets[r].push(user.frames[u]);
    previous = [r,u];
  }
  return reference.frames.map((frame,i) => ({ time: frame.time,
    relativePitch: ambiguous.has(i) ? null : median(buckets[i].map(f => f.relativePitch)),
    relativeDb: ambiguous.has(i) ? null : median(buckets[i].map(f => f.relativeDb)),
    breakBefore: breaks.has(i) }));
}

// Describe the measured absolute difference only. No pass bands, grades,
// correction directions or ranking: a reference is one possible example.
export function segmentObservation(segment, tab = 'pitch') {
  const pitch = tab === 'pitch';
  const error = pitch ? segment.pitchError : segment.levelError;
  if (!Number.isFinite(error) || error < 0) return {
    kind: 'uncertain', icon: '?', badge: '측정값 없음', label: '확인 어려움',
    observation: '비교할 목소리가 충분하지 않아요.',
    detail: '이 구간의 녹음을 다시 듣거나 새로 녹음할 수 있어요.',
  };
  const unit = pitch ? '반음' : 'dB';
  const value = error.toFixed(1);
  return {
    kind: 'observed', icon: '↔', badge: '측정한 차이', label: `${value}${unit} 차이`,
    observation: `이 구간에서 예시와 내 녹음의 상대적인 ${pitch ? '음높이' : '소리 크기'}는 평균 ${value}${unit} 차이가 나요.`,
    detail: pitch ? '반음은 음높이 차이의 단위예요. 각 목소리의 중간 높이를 기준으로 비교했어요.' : '각 녹음의 중간 크기를 기준으로 비교한 상대 dB 값이다.',
  };
}

// Deliberately artificial harmonic tones, NOT a human speech recording.
export function makeDemo(reference, sampleRate = 16000) {
  const stretch = 1.2;
  const samples = new Float32Array(Math.ceil(reference.duration * stretch * sampleRate));
  let phase = 0;
  for (let i=0;i<samples.length;i++) {
    const t = i / sampleRate / stretch;
    const idx = Math.min(reference.frames.length-1, Math.max(0, Math.round(t / .02)));
    const f = reference.frames[idx];
    if (!f?.pitchHz) continue;
    const part = t / reference.duration;
    const shift = part > .66 ? 4 * Math.min(1, (part-.66)/.12) : 0;
    phase += 2*Math.PI*f.pitchHz*Math.pow(2,shift/12)/sampleRate;
    const gain = Math.pow(10,(f.rmsDb + (part > .33 && part < .66 ? -5 : 0))/20);
    samples[i] = Math.min(.85,gain*1.4) * (.8*Math.sin(phase)+.2*Math.sin(phase*2));
  }
  return { samples, sampleRate };
}

export function wavBytes(samples, sampleRate) {
  const bytes = new ArrayBuffer(44 + samples.length*2), v=new DataView(bytes);
  const str=(at,text)=>{for(let i=0;i<text.length;i++)v.setUint8(at+i,text.charCodeAt(i));};
  str(0,'RIFF');v.setUint32(4,36+samples.length*2,true);str(8,'WAVE');str(12,'fmt ');v.setUint32(16,16,true);
  v.setUint16(20,1,true);v.setUint16(22,1,true);v.setUint32(24,sampleRate,true);v.setUint32(28,sampleRate*2,true);
  v.setUint16(32,2,true);v.setUint16(34,16,true);str(36,'data');v.setUint32(40,samples.length*2,true);
  for(let i=0;i<samples.length;i++) v.setInt16(44+i*2,Math.round(Math.max(-1,Math.min(1,samples[i]))*32767),true);
  return bytes;
}
