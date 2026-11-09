const LABELS = Object.freeze(Object.assign(Object.create(null), {
  a: 'A', 'ɑ': 'A', i: 'I', u: 'U', o: 'O', 'ɛ': 'E', 'ɯ': 'EU', 'ʌ': 'EO',
  ja: 'iA', 'jʌ': 'iEO', jo: 'iO', ju: 'iU', 'jɛ': 'iE',
  wa: 'oA', wi: 'uI', 'wɛ': 'oE', 'wʌ': 'wEO', 'ɰi': 'euI',
  p: 'B', b: 'B', 'p*': 'BB', 'b*': 'BB', 'pʰ': 'Ph', 'bʰ': 'Ph',
  t: 'D', d: 'D', 't*': 'DD', 'd*': 'DD', 'tʰ': 'Th', 'dʰ': 'Th',
  k: 'G', 'ɡ': 'G', 'k*': 'GG', 'ɡ*': 'GG', 'kʰ': 'Kh', 'ɡʰ': 'Kh',
  s: 'S', 's*': 'SS', h: 'H', 'tɕ': 'J', 'dʑ': 'J',
  'tɕ*': 'JJ', 'dʑ*': 'JJ', 'tɕʰ': 'CHh', 'dʑʰ': 'CHh',
  l: 'L', 'ɾ': 'R', m: 'M', n: 'N', 'ŋ': 'NG',
}));
const VOWELS = new Set(['A', 'I', 'U', 'O', 'E', 'EU', 'EO', 'iA', 'iEO', 'iO', 'iU', 'iE', 'oA', 'uI', 'oE', 'wEO', 'euI']);

export function ipaToPhones(phones) {
  if (!Array.isArray(phones) || phones.length > 1000 || phones.some(item => typeof item?.phone !== 'string')) {
    throw new Error('음소 목록이 올바르지 않다.');
  }
  return phones.map((item, i) => {
    let phone = LABELS[item.phone] ?? '[UNK]';
    // IPA voicing does not encode syllable position; use only the observed next vowel.
    if (!VOWELS.has(LABELS[phones[i + 1]?.phone])) phone = ({ B: 'p', D: 't', G: 'k' })[phone] ?? phone;
    return { ...item, phone };
  });
}
