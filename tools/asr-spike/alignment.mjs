// Throwaway feasibility spike, not imported by the product. No I/O.
// UTF-16 offsets refer to the ORIGINAL source, including decomposed Hangul.
function indexed(text) {
  const units = [];
  for (const { segment, index } of new Intl.Segmenter('ko', { granularity: 'grapheme' }).segment(text)) {
    for (const char of segment.normalize('NFC').toLocaleLowerCase('ko')) {
      if (/[\p{L}\p{N}]/u.test(char)) units.push({ char, start: index, end: index + segment.length });
    }
  }
  return units;
}

/** Conservative exact-suffix baseline. A range is an ASR text match, not proof
 * of correct pronunciation or a per-character timestamp. Repeated text stays
 * ambiguous; a caller can provide an explicitly selected practice range.
 * Skipped words are never included in the matched range. Rereading can move
 * backward. Partial hypotheses never move the confirmed range.
 */
export function alignFinal(source, hypothesis, { final = false, scope = [0, source.length] } = {}) {
  if (typeof source !== 'string' || typeof hypothesis !== 'string') throw new TypeError('Expected text');
  if (source.length > 8000 || hypothesis.length > 8000) throw new RangeError('Spike input too long');
  const [from, to] = scope;
  if (!Number.isInteger(from) || !Number.isInteger(to) || from < 0 || to > source.length || from >= to)
    throw new RangeError('Invalid source scope');
  if (!final) return { status: 'partial', range: null };
  const script = indexed(source).filter(unit => unit.start >= from && unit.end <= to);
  const heard = indexed(hypothesis);
  if (heard.length < 6) return { status: 'insufficient', range: null };
  // Match Unicode scalars, not string offsets: astral letters can occupy 2 units.
  const chars = script.map(unit => unit.char);
  for (let size = Math.min(heard.length, 80); size >= 6; size--) {
    const suffix = heard.slice(-size).map(unit => unit.char);
    const candidates = [];
    for (let start = 0; start <= chars.length - size; start++) {
      if (suffix.every((char, i) => chars[start + i] === char)) candidates.push(start);
    }
    if (!candidates.length) continue;
    if (candidates.length !== 1) return { status: 'ambiguous', range: null };
    const start = script[candidates[0]].start;
    const end = script[candidates[0] + size - 1].end;
    return { status: 'matched', range: { start, end }, text: source.slice(start, end),
      before: source.slice(Math.max(from, start - 40), start), after: source.slice(end, Math.min(to, end + 40)),
      matchedCharacters: size, scope: [from, to] };
  }
  return { status: 'uncertain', range: null };
}
