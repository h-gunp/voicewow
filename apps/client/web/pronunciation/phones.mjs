// The pinned IPA model expects raw 16 kHz PCM, with normalization disabled.
export function prepareSamples(samples, sampleRate) {
  if (!(samples instanceof Float32Array) || sampleRate !== 16000
    || samples.length < 3200 || samples.length > 320000) {
    throw new Error('16kHz 모노 음성을 0.2초 이상 20초 이하로 입력해야 한다.');
  }
  let mean = 0;
  for (const value of samples) {
    if (!Number.isFinite(value) || Math.abs(value) > 1.001) throw new Error('오디오 값이 올바르지 않다.');
    mean += value / samples.length;
  }
  let variance = 0;
  for (const value of samples) variance += (value - mean) ** 2 / samples.length;
  if (variance < 1e-10) throw new Error('분석할 소리가 없거나 너무 작다. 다시 녹음해야 한다.');
  return samples;
}

export function decodePhones(logits, dims, vocab) {
  if (!(logits instanceof Float32Array) || !Array.isArray(dims) || dims.length !== 3
    || dims[0] !== 1 || !Number.isInteger(dims[1]) || dims[1] < 1 || dims[1] > 1000
    || dims[2] !== 55 || logits.length !== dims[1] * dims[2] || vocab?.['[PAD]'] !== 0) {
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
    if (id !== 0 && phone !== ' ') {
      if (id === previous) phones.at(-1).endFrame = frame + 1;
      else phones.push({ phone, startFrame: frame, endFrame: frame + 1 });
    }
    previous = id;
  }
  return phones;
}

const ONSET = { G: 'ㄱ', GG: 'ㄲ', N: 'ㄴ', D: 'ㄷ', DD: 'ㄸ', L: 'ㄹ', R: 'ㄹ', M: 'ㅁ', B: 'ㅂ', BB: 'ㅃ', S: 'ㅅ', SS: 'ㅆ', J: 'ㅈ', JJ: 'ㅉ', CHh: 'ㅊ', Kh: 'ㅋ', Th: 'ㅌ', Ph: 'ㅍ', H: 'ㅎ' };
const CODA = { k: 'ㄱ', N: 'ㄴ', t: 'ㄷ', L: 'ㄹ', R: 'ㄹ', M: 'ㅁ', p: 'ㅂ', NG: 'ㅇ' };
const VOWEL = { A: 'ㅏ', E: 'ㅔ', EO: 'ㅓ', EU: 'ㅡ', I: 'ㅣ', O: 'ㅗ', U: 'ㅜ', iA: 'ㅑ', iE: 'ㅖ', iEO: 'ㅕ', iO: 'ㅛ', iU: 'ㅠ', oA: 'ㅘ', oE: 'ㅞ', uI: 'ㅟ', wEO: 'ㅝ', euI: 'ㅢ' };
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
