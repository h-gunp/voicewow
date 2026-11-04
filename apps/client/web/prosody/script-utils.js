// Script preparation only: no speech recognition, network or browser side effects.
export const MAX_SCRIPT_CHARACTERS = 2000;
export const MAX_PRACTICE_CHARACTERS = 100;
export const MAX_PRACTICE_SEGMENTS = 30;
// Text preparation limits, not word timestamps or speech evaluation criteria.
export const TARGET_PRACTICE_UNIT_CHARACTERS = 50;
export const MAX_PRACTICE_UNIT_CHARACTERS = 60;
export const MAX_PRACTICE_UNITS = 60;

// A reading aid for the graph. These text boundaries are not audio timestamps.
export function splitRegionText(text, count) {
  if (count < 1) return [];
  const graphemes = typeof Intl.Segmenter === 'function'
    ? Array.from(new Intl.Segmenter('ko', { granularity: 'grapheme' }).segment(text.trim()), part => part.segment)
    : Array.from(text.trim());
  const visible = graphemes.flatMap((part, index) => /[\p{L}\p{N}\p{S}]/u.test(part) ? [index] : []);
  if (visible.length < count) return [];

  const snippets = [];
  let start = 0;
  let consumed = 0;
  for (let remaining = count; remaining > 1; remaining--) {
    const lastCut = visible.length - remaining + 1;
    const balanced = Math.round(visible.length * (count - remaining + 1) / count);
    const target = Math.min(lastCut, Math.max(consumed + 1, balanced));
    const cut = [target, target - 1, target + 1].find(i => i > consumed
      && i <= lastCut && /\s/u.test(graphemes[visible[i] - 1])) ?? target;
    const end = visible[cut];
    snippets.push(graphemes.slice(start, end).join('').trim());
    start = end;
    consumed = cut;
  }
  snippets.push(graphemes.slice(start).join('').trim());
  return snippets;
}

function protectedPeriod(characters, index) {
  const before = characters[index - 1] || '';
  const after = characters[index + 1] || '';
  if (/\d/u.test(before) && /\d/u.test(after)) return true;
  // Keep initials, common abbreviations and dotted names intact. These rules
  // are deliberately small; sentence splitting is not linguistic alignment.
  if (/[A-Za-z]/u.test(before) && /[A-Za-z]/u.test(after)) return true;
  const prefix = characters.slice(0, index).join('');
  const token = prefix.match(/([A-Za-z][A-Za-z.]*)$/u)?.[1] || '';
  return /^(?:Mr|Mrs|Ms|Dr|Prof|Sr|Jr|St|vs|etc|e\.g|i\.e)$/iu.test(token)
    || /^(?:[A-Za-z]\.)+[A-Za-z]$/u.test(token)
    || /^[A-Z]$/u.test(token);
}

function splitSentences(line) {
  const characters = Array.from(line);
  const sentences = [];
  let start = 0;
  for (let index = 0; index < characters.length; index++) {
    const character = characters[index];
    if (!/[.!?。！？]/u.test(character)) continue;
    if (character === '.' && protectedPeriod(characters, index)) continue;
    // Treat "?!", "..." and following closing quotes as one sentence ending.
    while (index + 1 < characters.length && /[.!?。！？”’"'」』）)\]]/u.test(characters[index + 1])) index++;
    sentences.push(characters.slice(start, index + 1).join(''));
    start = index + 1;
  }
  if (start < characters.length) sentences.push(characters.slice(start).join(''));
  return sentences;
}

function shortChunks(sentence) {
  const words = sentence.trim().split(/\s+/u).filter(Boolean);
  const chunks = [];
  let current = '';
  let currentLength = 0;
  for (const word of words) {
    const characters = Array.from(word);
    if (current && currentLength + 1 + characters.length <= MAX_PRACTICE_CHARACTERS) {
      current += ` ${word}`;
      currentLength += 1 + characters.length;
      continue;
    }
    if (current) chunks.push(current);
    current = '';
    currentLength = 0;
    while (characters.length > MAX_PRACTICE_CHARACTERS) {
      chunks.push(characters.splice(0, MAX_PRACTICE_CHARACTERS).join(''));
    }
    current = characters.join('');
    currentLength = characters.length;
  }
  if (current) chunks.push(current);
  return chunks;
}

/** Returns short practice sections, preserving all non-whitespace characters.
 * Boundaries are text-based practice aids, not detected speech/word alignment.
 * Long sentences are divided at words, or at character boundaries as a fallback.
 */
export function parseScript(text) {
  if (typeof text !== 'string') throw new TypeError('연습할 대본을 글로 입력해 주세요.');
  const source = text.trim();
  if (!source) throw new Error('연습할 대본을 먼저 입력해 주세요.');
  if (Array.from(source).length > MAX_SCRIPT_CHARACTERS) {
    throw new Error(`대본은 ${MAX_SCRIPT_CHARACTERS.toLocaleString('ko-KR')}자 이하로 입력해 주세요.`);
  }
  const segments = source.split(/\r\n|[\n\r\u2028\u2029]/u)
    .flatMap(splitSentences).flatMap(shortChunks);
  if (segments.length > MAX_PRACTICE_SEGMENTS) {
    throw new Error(`한 번에 ${MAX_PRACTICE_SEGMENTS}개 구간까지 연습할 수 있어요. 대본을 조금 나눠 입력해 주세요.`);
  }
  return segments;
}

function practiceChunks(sentence) {
  const chunks = [];
  let remaining = Array.from(sentence);
  while (remaining.length > MAX_PRACTICE_UNIT_CHARACTERS) {
    // Balance a short tail instead of making a 50-character chunk plus a
    // one-word fragment. Boundary choice uses text only, never audio duration.
    const target = Math.ceil(remaining.length / Math.ceil(remaining.length / TARGET_PRACTICE_UNIT_CHARACTERS));
    const maxCut = Math.min(MAX_PRACTICE_UNIT_CHARACTERS, remaining.length - 15);
    const minCut = Math.min(20, target);
    const punctuation = [], spaces = [];
    for (let i = minCut; i <= maxCut; i++) {
      const before = remaining[i - 1], after = remaining[i];
      if (/[,，、;；:：]/u.test(before)
        && !(/\d/u.test(remaining[i - 2] || '') && /\d/u.test(after || ''))) punctuation.push(i);
      if (/\s/u.test(after || '')) spaces.push(i);
    }
    const closest = values => values.reduce((best, value) =>
      Math.abs(value - target) < Math.abs(best - target) ? value : best);
    const cut = punctuation.length ? closest(punctuation)
      : spaces.length ? closest(spaces) : Math.min(target, maxCut);
    const part = remaining.slice(0, cut).join('').trim();
    if (part) chunks.push(part);
    remaining = Array.from(remaining.slice(cut).join('').trimStart());
  }
  const last = remaining.join('').trim();
  if (last) chunks.push(last);
  return chunks;
}

/** Prepare one short text at a time, keeping its original sentence context.
 * Indices are zero-based. Whitespace is normalized; all other code points keep
 * their order. Manual line breaks always separate sentences. A long unspaced
 * sentence may be divided at character boundaries as a text practice aid;
 * these are never detected word, syllable or audio-time boundaries.
 */
export function parsePracticeScript(text) {
  if (typeof text !== 'string') throw new TypeError('연습할 대본을 글로 입력해 주세요.');
  const source = text.trim();
  if (!source) throw new Error('연습할 대본을 먼저 입력해 주세요.');
  if (Array.from(source).length > MAX_SCRIPT_CHARACTERS) {
    throw new Error(`대본은 ${MAX_SCRIPT_CHARACTERS.toLocaleString('ko-KR')}자 이하로 입력해 주세요.`);
  }
  const sentences = source.split(/\r\n|[\n\r\u2028\u2029]/u)
    .flatMap(splitSentences).map(sentence => sentence.replace(/\s+/gu, ' ').trim()).filter(Boolean);
  const units = sentences.flatMap((sentenceText, sentenceIndex) => {
    const parts = practiceChunks(sentenceText);
    return parts.map((part, partIndex) => ({
      text: part, sentenceText, sentenceIndex, partIndex, partCount: parts.length,
    }));
  });
  if (units.length > MAX_PRACTICE_UNITS) {
    throw new Error(`한 번에 ${MAX_PRACTICE_UNITS}개 연습 조각까지 준비할 수 있어요. 대본을 조금 나눠 입력해 주세요.`);
  }
  return units;
}

/** Only explicitly local Korean voices may be used for script playback.
 * Returning null lets the UI explain that this device has no local Korean voice.
 */
export function selectLocalKoreanVoice(voices) {
  if (!Array.isArray(voices)) return null;
  const available = voices.filter(voice => voice?.localService === true
    && /^ko(?:[-_]kr)?$/iu.test(voice.lang || ''));
  return available.find(voice => voice.default === true) || available[0] || null;
}
