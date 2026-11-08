// MFA phone labels are observations, not orthographic Korean or a pronunciation score.
export function prepareSamples(samples, sampleRate) {
  if (!(samples instanceof Float32Array) || sampleRate !== 16000
    || samples.length < 3200 || samples.length > 320000) {
    throw new Error('16kHz 모노 음성을 0.2초 이상 20초 이하로 입력해야 한다.');
  }
  let mean = 0, peak = 0;
  for (const value of samples) {
    if (!Number.isFinite(value) || Math.abs(value) > 1.001) throw new Error('오디오 값이 올바르지 않다.');
    mean += value / samples.length;
    peak = Math.max(peak, Math.abs(value));
  }
  let variance = 0;
  for (const value of samples) variance += (value - mean) ** 2 / samples.length;
  if (variance < 1e-10) throw new Error('분석할 소리가 없거나 너무 작다. 다시 녹음해야 한다.');

  // Anchor context to samples, not frames, so button timing cannot shift the model's input grid.
  const threshold = Math.max(1e-4, peak * .01);
  let first = 0, last = samples.length - 1;
  while (first < samples.length && Math.abs(samples[first]) < threshold) first++;
  while (last >= first && Math.abs(samples[last]) < threshold) last--;
  const start = first - 6400, end = last + 1 + 6400;
  let input = samples;
  if (first <= last && end - start <= 320000) {
    input = new Float32Array(end - start);
    const sourceStart = Math.max(0, start), sourceEnd = Math.min(samples.length, end);
    input.set(samples.subarray(sourceStart, sourceEnd), sourceStart - start);
    mean = 0;
    for (const value of input) mean += value / input.length;
    variance = 0;
    for (const value of input) variance += (value - mean) ** 2 / input.length;
  }
  // Silence was rejected above; an additive epsilon would attenuate quiet speech differently.
  if (!(variance > 0) || !Number.isFinite(variance)) throw new Error('분석할 소리가 없다. 다시 녹음해야 한다.');
  const scale = Math.sqrt(variance);
  return Float32Array.from(input, value => (value - mean) / scale);
}

export function decodePhones(logits, dims, vocab) {
  if (!(logits instanceof Float32Array) || !Array.isArray(dims) || dims.length !== 3
    || dims[0] !== 1 || !Number.isInteger(dims[1]) || dims[1] < 1 || dims[1] > 1000
    || dims[2] !== 45 || logits.length !== dims[1] * dims[2] || vocab?.['[PAD]'] !== 42) {
    throw new Error('음소 모델 출력 형식이 올바르지 않다.');
  }
  const byId = new Map(Object.entries(vocab).map(([phone, id]) => [id, phone]));
  const phones = [];
  let previous = -1;
  for (let frame = 0; frame < dims[1]; frame++) {
    const offset = frame * dims[2];
    let id = 0;
    for (let c = 0; c < dims[2]; c++) {
      if (!Number.isFinite(logits[offset + c])) throw new Error('음소 모델 출력에 유효하지 않은 수치가 있다.');
      if (logits[offset + c] > logits[offset + id]) id = c;
    }
    const phone = byId.get(id);
    if (phone === undefined) throw new Error('음소 사전과 모델이 일치하지 않는다.');
    if (id !== 42 && phone !== '|') {
      if (id === previous) phones.at(-1).endFrame = frame + 1;
      else phones.push({ phone, startFrame: frame, endFrame: frame + 1 });
    }
    previous = id;
  }
  return phones;
}

const ONSET = { G: 'ㄱ', GG: 'ㄲ', N: 'ㄴ', D: 'ㄷ', DD: 'ㄸ', L: 'ㄹ', R: 'ㄹ', M: 'ㅁ', B: 'ㅂ', BB: 'ㅃ', S: 'ㅅ', SS: 'ㅆ', J: 'ㅈ', JJ: 'ㅉ', CHh: 'ㅊ', Kh: 'ㅋ', Th: 'ㅌ', Ph: 'ㅍ', H: 'ㅎ' };
const CODA = { k: 'ㄱ', N: 'ㄴ', t: 'ㄷ', L: 'ㄹ', R: 'ㄹ', M: 'ㅁ', p: 'ㅂ', NG: 'ㅇ' };
const VOWEL = { A: 'ㅏ', E: 'ㅔ', EO: 'ㅓ', EU: 'ㅡ', I: 'ㅣ', O: 'ㅗ', U: 'ㅜ', iA: 'ㅑ', iE: 'ㅖ', iEO: 'ㅕ', iO: 'ㅛ', iU: 'ㅠ', oA: 'ㅘ', oE: 'ㅞ', uI: 'ㅟ', euI: 'ㅢ' };
const MERGED = { E: 'ㅐ/ㅔ 구분 불가', iE: 'ㅒ/ㅖ 구분 불가', oE: 'ㅙ/ㅚ/ㅞ 구분 불가' };
const INITIALS = 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ';
const MEDIALS = 'ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ';
const FINALS = ' ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ';

export function phonesToHangul(phones) {
  if (!Array.isArray(phones) || phones.length > 1000 || phones.some(item => typeof item?.phone !== 'string')) {
    throw new Error('음소 목록이 올바르지 않다.');
  }
  const segments = [];
  let i = 0;
  while (i < phones.length) {
    const start = i, current = phones[i].phone;
    const notes = [];
    let initial = 'ㅇ', vowelPhone = current;
    if (ONSET[current] && VOWEL[phones[i + 1]?.phone]) {
      initial = ONSET[current]; vowelPhone = phones[++i].phone;
    }
    if (!VOWEL[vowelPhone]) {
      const text = ONSET[current] ?? CODA[current] ?? '□';
      notes.push(current === 'uEO' ? 'uEO의 원모델 IPA 표기 불일치로 한글 변환을 보류한다.' : '음절로 확정할 수 없는 음소다.');
      segments.push({ text, phoneStart: start, phoneEnd: ++i, uncertain: true, notes });
      continue;
    }
    if (MERGED[vowelPhone]) notes.push(MERGED[vowelPhone]);
    if (start > 0 && VOWEL[phones[start - 1].phone] && CODA[current]) notes.push('초성·종성 경계가 모호하다.');
    i++;
    let final = ' ';
    const next = phones[i]?.phone;
    if (CODA[next]) {
      if (ONSET[next] && VOWEL[phones[i + 1]?.phone]) notes.push('초성·종성 경계가 모호하다.');
      else { final = CODA[next]; i++; }
    }
    const text = String.fromCharCode(0xac00 + (INITIALS.indexOf(initial) * 21 + MEDIALS.indexOf(VOWEL[vowelPhone])) * 28 + FINALS.indexOf(final));
    segments.push({ text, phoneStart: start, phoneEnd: i, uncertain: notes.length > 0, notes });
  }
  return { text: segments.map(segment => segment.text).join(''), uncertain: segments.some(segment => segment.uncertain), segments };
}
