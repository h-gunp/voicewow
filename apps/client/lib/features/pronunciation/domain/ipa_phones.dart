const _labels = <String, String>{
  'a': 'A',
  'ɑ': 'A',
  'i': 'I',
  'u': 'U',
  'o': 'O',
  'ɛ': 'E',
  'ɯ': 'EU',
  'ʌ': 'EO',
  'ja': 'iA',
  'jʌ': 'iEO',
  'jo': 'iO',
  'ju': 'iU',
  'jɛ': 'iE',
  'wa': 'oA',
  'wi': 'uI',
  'wɛ': 'oE',
  'wʌ': 'wEO',
  'ɰi': 'euI',
  'p': 'B',
  'b': 'B',
  'p*': 'BB',
  'b*': 'BB',
  'pʰ': 'Ph',
  'bʰ': 'Ph',
  't': 'D',
  'd': 'D',
  't*': 'DD',
  'd*': 'DD',
  'tʰ': 'Th',
  'dʰ': 'Th',
  'k': 'G',
  'ɡ': 'G',
  'k*': 'GG',
  'ɡ*': 'GG',
  'kʰ': 'Kh',
  'ɡʰ': 'Kh',
  's': 'S',
  's*': 'SS',
  'h': 'H',
  'tɕ': 'J',
  'dʑ': 'J',
  'tɕ*': 'JJ',
  'dʑ*': 'JJ',
  'tɕʰ': 'CHh',
  'dʑʰ': 'CHh',
  'l': 'L',
  'ɾ': 'R',
  'm': 'M',
  'n': 'N',
  'ŋ': 'NG',
};
const _vowels = {
  'A',
  'I',
  'U',
  'O',
  'E',
  'EU',
  'EO',
  'iA',
  'iEO',
  'iO',
  'iU',
  'iE',
  'oA',
  'uI',
  'oE',
  'wEO',
  'euI',
};

List<String> ipaToPhones(List<String> phones) {
  if (phones.length > 1000 || phones.any((p) => p.isEmpty || p.length > 32)) {
    throw ArgumentError('음소 목록이 올바르지 않다.');
  }
  return List.generate(phones.length, (i) {
    var phone = _labels[phones[i]] ?? '[UNK]';
    // Voicing is independent of syllable position; never use the expected reading here.
    if (i + 1 == phones.length || !_vowels.contains(_labels[phones[i + 1]])) {
      phone = const {'B': 'p', 'D': 't', 'G': 'k'}[phone] ?? phone;
    }
    return phone;
  }, growable: false);
}
