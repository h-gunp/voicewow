import 'dart:typed_data';

enum ComparisonMark { match, different, uncertain }

class PronunciationSpan {
  const PronunciationSpan({required this.text, required this.mark});

  final String text;
  final ComparisonMark mark;
}

class PronunciationComparison {
  const PronunciationComparison({
    required this.reference,
    required this.observed,
    required this.expected,
    required this.notes,
    required this.differences,
  });

  final String reference;
  final List<PronunciationSpan> observed;
  final List<PronunciationSpan> expected;
  final List<String> notes;
  final List<String> differences;
}

PronunciationComparison comparePronunciation({
  required List<String> phones,
  required List<String> references,
  bool referenceIsApproximate = false,
}) {
  if (phones.length > 1000 ||
      phones.any((phone) => phone.isEmpty || phone.length > 32) ||
      references.isEmpty ||
      references.length > 16 ||
      references.any(
        (text) => text.trim().isEmpty || text.runes.length > 300,
      )) {
    throw ArgumentError('음소는 1000개, 참고 발음은 300자씩 16개 이내여야 한다.');
  }
  final notes = <String>{'색상은 추정 음소와 참고 발음의 비교이며 실제 발음 정확도를 뜻하지 않는다.'};
  if (referenceIsApproximate) {
    notes.add('규칙 기반 참고 읽기와의 실험적 비교다. 모든 허용 발음과 음운 변화를 반영하지 못한다.');
  }
  final observed = _observe(phones, notes);
  var reference = references.first;
  var expected = _reference(reference);
  var alignment = _align(observed.phones, expected.phones);
  final tiedReferences = <(_Reading, _Alignment)>[];
  for (final candidate in references.skip(1)) {
    final reading = _reference(candidate);
    final candidateAlignment = _align(observed.phones, reading.phones);
    if (candidateAlignment.distance < alignment.distance) {
      reference = candidate;
      expected = reading;
      alignment = candidateAlignment;
      tiedReferences.clear();
    } else if (candidateAlignment.distance == alignment.distance) {
      tiedReferences.add((reading, candidateAlignment));
    }
  }
  if (RegExp(r'\s').hasMatch(reference)) {
    notes.add('어절 경계의 차이는 이어 읽기에 따른 변화일 수 있어 비교를 보류한다.');
  }
  if (phones.isEmpty) {
    notes.add('비교할 음소가 없다. 소리를 확인하고 다시 녹음해야 한다.');
    return PronunciationComparison(
      reference: reference,
      observed: const [],
      expected: [
        for (final unit in expected.units)
          PronunciationSpan(text: unit.text, mark: ComparisonMark.uncertain),
      ],
      notes: notes.toList(growable: false),
      differences: const [],
    );
  }
  if (alignment.observedAmbiguous.any((value) => value) ||
      alignment.expectedAmbiguous.any((value) => value)) {
    notes.add('최소 차이의 음소 정렬이 여러 개여서 해당 구간의 비교를 보류한다.');
  }
  if (expected.units.any((unit) => unit.unresolved)) {
    notes.add('참고 발음에 음소로 확정할 수 없는 글자가 있어 해당 구간을 보류한다.');
  }
  final observedMarks = _marks(
    observed,
    expected,
    alignment.observedPairs,
    alignment.expectedPairs,
    alignment.observedAmbiguous,
    alignment.expectedAmbiguous,
  );
  final expectedMarks = _marks(
    expected,
    observed,
    alignment.expectedPairs,
    alignment.observedPairs,
    alignment.expectedAmbiguous,
    alignment.observedAmbiguous,
  );
  for (final (alternative, alternateAlignment) in tiedReferences) {
    final alternateMarks = _marks(
      observed,
      alternative,
      alternateAlignment.observedPairs,
      alternateAlignment.expectedPairs,
      alternateAlignment.observedAmbiguous,
      alternateAlignment.expectedAmbiguous,
    );
    for (var i = 0; i < observed.units.length; i++) {
      if (observedMarks[i] == alternateMarks[i]) continue;
      notes.add('같은 최소 차이의 허용 기준이 여러 개여서 비교가 달라지는 구간을 보류한다.');
      observedMarks[i] = ComparisonMark.uncertain;
      final unit = observed.units[i];
      for (var token = unit.start; token < unit.end; token++) {
        final paired = alignment.observedPairs[token];
        if (paired >= 0)
          expectedMarks[expected.owners[paired]] = ComparisonMark.uncertain;
      }
    }
    if (expected.phones.join(' ') != alternative.phones.join(' ')) {
      for (var i = 0; i < expected.units.length; i++) {
        final unit = expected.units[i];
        if (expectedMarks[i] == ComparisonMark.different &&
            alignment.expectedPairs
                .sublist(unit.start, unit.end)
                .every((pair) => pair < 0)) {
          expectedMarks[i] = ComparisonMark.uncertain;
          notes.add('같은 최소 차이의 허용 기준이 여러 개여서 비교가 달라지는 구간을 보류한다.');
        }
      }
    }
  }
  final differences = <String>{};
  for (var index = 0; index < expected.units.length; index++) {
    if (expectedMarks[index] != ComparisonMark.different) continue;
    final unit = expected.units[index];
    final counterparts = <int>{};
    for (var phone = unit.start; phone < unit.end; phone++) {
      final paired = alignment.expectedPairs[phone];
      if (paired >= 0) counterparts.add(observed.owners[paired]);
    }
    if (counterparts.isEmpty) {
      differences.add('기준 ${unit.text}: 인식에서 누락');
    } else if (counterparts.every(
      (i) => observedMarks[i] != ComparisonMark.uncertain,
    )) {
      differences.add(
        '기준 ${unit.text} → 인식 ${counterparts.map((i) => observed.units[i].text).join()}',
      );
    } else {
      differences.add('기준 ${unit.text}: 일부 음소 차이');
    }
  }
  for (var index = 0; index < observed.units.length; index++) {
    if (observedMarks[index] != ComparisonMark.different) continue;
    final unit = observed.units[index];
    if (alignment.observedPairs
        .sublist(unit.start, unit.end)
        .every((pair) => pair < 0)) {
      differences.add('추가로 인식: ${unit.text}');
    }
  }
  return PronunciationComparison(
    reference: reference,
    observed: [
      for (var i = 0; i < observed.units.length; i++)
        PronunciationSpan(text: observed.units[i].text, mark: observedMarks[i]),
    ],
    expected: [
      for (var i = 0; i < expected.units.length; i++)
        PronunciationSpan(text: expected.units[i].text, mark: expectedMarks[i]),
    ],
    notes: notes.toList(growable: false),
    differences: differences.toList(growable: false),
  );
}

const _onsets = <String, String>{
  'G': 'ㄱ',
  'GG': 'ㄲ',
  'N': 'ㄴ',
  'D': 'ㄷ',
  'DD': 'ㄸ',
  'L': 'ㄹ',
  'R': 'ㄹ',
  'M': 'ㅁ',
  'B': 'ㅂ',
  'BB': 'ㅃ',
  'S': 'ㅅ',
  'SS': 'ㅆ',
  'J': 'ㅈ',
  'JJ': 'ㅉ',
  'CHh': 'ㅊ',
  'Kh': 'ㅋ',
  'Th': 'ㅌ',
  'Ph': 'ㅍ',
  'H': 'ㅎ',
};
const _codas = <String, String>{
  'k': 'ㄱ',
  'N': 'ㄴ',
  't': 'ㄷ',
  'L': 'ㄹ',
  'R': 'ㄹ',
  'M': 'ㅁ',
  'p': 'ㅂ',
  'NG': 'ㅇ',
};
const _vowels = <String, String>{
  'A': 'ㅏ',
  'E': 'ㅔ',
  'EO': 'ㅓ',
  'EU': 'ㅡ',
  'I': 'ㅣ',
  'O': 'ㅗ',
  'U': 'ㅜ',
  'iA': 'ㅑ',
  'iE': 'ㅖ',
  'iEO': 'ㅕ',
  'iO': 'ㅛ',
  'iU': 'ㅠ',
  'oA': 'ㅘ',
  'oE': 'ㅞ',
  'uI': 'ㅟ',
  'euI': 'ㅢ',
};
const _merged = <String, String>{
  'E': 'ㅐ/ㅔ 구분 불가',
  'iE': 'ㅒ/ㅖ 구분 불가',
  'oE': 'ㅙ/ㅚ/ㅞ 구분 불가',
};
const _initials = 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ';
const _medials = 'ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ';
const _finals = ' ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ';
const _initialPhones = [
  'G',
  'GG',
  'N',
  'D',
  'DD',
  'L',
  'M',
  'B',
  'BB',
  'S',
  'SS',
  '',
  'J',
  'JJ',
  'CHh',
  'Kh',
  'Th',
  'Ph',
  'H',
];
const _medialPhones = [
  'A',
  'E',
  'iA',
  'iE',
  'EO',
  'E',
  'iEO',
  'iE',
  'O',
  'oA',
  'oE',
  'oE',
  'iO',
  'U',
  'uEO',
  'oE',
  'uI',
  'iU',
  'EU',
  'euI',
  'I',
];
const _finalPhones = [
  '',
  'k',
  'k',
  '?',
  'N',
  '?',
  '?',
  't',
  'L',
  '?',
  '?',
  '?',
  '?',
  '?',
  '?',
  '?',
  'M',
  'p',
  '?',
  't',
  't',
  'NG',
  't',
  't',
  'k',
  't',
  'p',
  't',
];

class _Unit {
  _Unit(
    this.text,
    this.start,
    this.end, {
    this.uncertain = false,
    this.unresolved = false,
  });
  final String text;
  final int start;
  final int end;
  bool uncertain;
  final bool unresolved;
}

class _Reading {
  final units = <_Unit>[];
  final phones = <String>[];
  final owners = <int>[];
  final wordBoundaryPhones = <int>{};

  void add(
    String text,
    List<String> labels, {
    bool uncertain = false,
    bool unresolved = false,
  }) {
    final start = phones.length;
    phones.addAll(labels.map(_canonical));
    owners.addAll(List.filled(labels.length, units.length));
    units.add(
      _Unit(
        text,
        start,
        phones.length,
        uncertain: uncertain,
        unresolved: unresolved,
      ),
    );
  }
}

String _canonical(String phone) => phone == 'R' ? 'L' : phone;
bool _known(String phone) =>
    _onsets.containsKey(phone) ||
    _codas.containsKey(phone) ||
    _vowels.containsKey(phone);

// This mirrors the spike display; reference spelling must never repair the observation.
_Reading _observe(List<String> phones, Set<String> notes) {
  final reading = _Reading();
  var i = 0;
  while (i < phones.length) {
    final start = i;
    final current = phones[i];
    var initial = 'ㅇ';
    var vowel = current;
    var uncertain = false;
    if (_onsets.containsKey(current) &&
        i + 1 < phones.length &&
        _vowels.containsKey(phones[i + 1])) {
      initial = _onsets[current]!;
      vowel = phones[++i];
    }
    if (!_vowels.containsKey(vowel)) {
      notes.add(
        current == 'uEO'
            ? 'uEO의 원모델 IPA 표기 불일치로 한글 변환을 보류한다.'
            : '음절로 확정할 수 없는 음소는 자모 또는 □로 표시하고 비교를 보류한다.',
      );
      reading.add(_onsets[current] ?? _codas[current] ?? '□', [
        current,
      ], unresolved: true);
      i++;
      continue;
    }
    if (_merged.containsKey(vowel)) {
      notes.add(_merged[vowel]!);
      uncertain = true;
    }
    if (start > 0 &&
        _vowels.containsKey(phones[start - 1]) &&
        _codas.containsKey(current)) {
      notes.add('초성·종성 배치는 추정 표기이며 색상은 음소열의 일치와 차이를 비교한다.');
    }
    i++;
    var finalJamo = ' ';
    if (i < phones.length && _codas.containsKey(phones[i])) {
      if (_onsets.containsKey(phones[i]) &&
          i + 1 < phones.length &&
          _vowels.containsKey(phones[i + 1])) {
        notes.add('초성·종성 배치는 추정 표기이며 색상은 음소열의 일치와 차이를 비교한다.');
      } else {
        finalJamo = _codas[phones[i++]]!;
      }
    }
    final text = String.fromCharCode(
      0xac00 +
          (_initials.indexOf(initial) * 21 +
                  _medials.indexOf(_vowels[vowel]!)) *
              28 +
          _finals.indexOf(finalJamo),
    );
    reading.add(text, phones.sublist(start, i), uncertain: uncertain);
  }
  return reading;
}

_Reading _reference(String text) {
  final reading = _Reading();
  for (final rune in text.runes) {
    final character = String.fromCharCode(rune);
    final syllable = rune - 0xac00;
    if (syllable >= 0 && syllable < 11172) {
      final initial = _initialPhones[syllable ~/ 588];
      final medial = _medialPhones[(syllable % 588) ~/ 28];
      final finalPhone = _finalPhones[syllable % 28];
      reading.add(
        character,
        [
          if (initial.isNotEmpty) initial,
          medial,
          if (finalPhone.isNotEmpty) finalPhone,
        ],
        uncertain: _merged.containsKey(medial),
        unresolved: finalPhone == '?' || medial == 'uEO',
      );
    } else if (RegExp(
      r'''[\s.,!?…·:;\[\](){}'"“”‘’\-]''',
    ).hasMatch(character)) {
      reading.add(character, [], uncertain: true);
    } else {
      reading.add(character, ['?'], unresolved: true);
    }
  }
  // shortcut: references omit cross-word changes; defer boundary differences until those rules are supported.
  for (var i = 1; i + 1 < reading.units.length; i++) {
    if (!RegExp(r'\s').hasMatch(reading.units[i].text)) continue;
    for (final direction in [-1, 1]) {
      var adjacent = i + direction;
      while (adjacent >= 0 &&
          adjacent < reading.units.length &&
          reading.units[adjacent].start == reading.units[adjacent].end) {
        adjacent += direction;
      }
      if (adjacent < 0 || adjacent >= reading.units.length) continue;
      final unit = reading.units[adjacent];
      reading.wordBoundaryPhones.add(direction < 0 ? unit.end - 1 : unit.start);
    }
  }
  return reading;
}

class _Alignment {
  _Alignment(this.distance, int observedLength, int expectedLength)
    : observedPairs = List.filled(observedLength, -2),
      expectedPairs = List.filled(expectedLength, -2),
      observedAmbiguous = List.filled(observedLength, false),
      expectedAmbiguous = List.filled(expectedLength, false);
  final int distance;
  final List<int> observedPairs;
  final List<int> expectedPairs;
  final List<bool> observedAmbiguous;
  final List<bool> expectedAmbiguous;
}

int _min3(int a, int b, int c) {
  final first = a < b ? a : b;
  return first < c ? first : c;
}

_Alignment _align(List<String> observed, List<String> expected) {
  final n = observed.length;
  final m = expected.length;
  final forward = List.generate(n + 1, (_) => Uint16List(m + 1));
  final backward = List.generate(n + 1, (_) => Uint16List(m + 1));
  for (var i = 0; i <= n; i++) {
    forward[i][0] = i;
    backward[i][m] = n - i;
  }
  for (var j = 0; j <= m; j++) {
    forward[0][j] = j;
    backward[n][j] = m - j;
  }
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      forward[i][j] = _min3(
        forward[i - 1][j] + 1,
        forward[i][j - 1] + 1,
        forward[i - 1][j - 1] + (observed[i - 1] == expected[j - 1] ? 0 : 1),
      );
    }
  }
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      backward[i][j] = _min3(
        backward[i + 1][j] + 1,
        backward[i][j + 1] + 1,
        backward[i + 1][j + 1] + (observed[i] == expected[j] ? 0 : 1),
      );
    }
  }
  final result = _Alignment(forward[n][m], n, m);
  void record(
    List<int> pairs,
    List<bool> ambiguous,
    int index,
    int counterpart,
  ) {
    if (pairs[index] == -2) {
      pairs[index] = counterpart;
    } else if (pairs[index] != counterpart) {
      ambiguous[index] = true;
    }
  }

  // An edge belongs to an optimum iff its prefix + edge + suffix equals the minimum.
  for (var i = 0; i <= n; i++) {
    for (var j = 0; j <= m; j++) {
      final prefix = forward[i][j];
      if (i < n &&
          j < m &&
          prefix +
                  (observed[i] == expected[j] ? 0 : 1) +
                  backward[i + 1][j + 1] ==
              result.distance) {
        record(result.observedPairs, result.observedAmbiguous, i, j);
        record(result.expectedPairs, result.expectedAmbiguous, j, i);
      }
      if (i < n && prefix + 1 + backward[i + 1][j] == result.distance) {
        record(result.observedPairs, result.observedAmbiguous, i, -1);
      }
      if (j < m && prefix + 1 + backward[i][j + 1] == result.distance) {
        record(result.expectedPairs, result.expectedAmbiguous, j, -1);
      }
    }
  }
  return result;
}

List<ComparisonMark> _marks(
  _Reading reading,
  _Reading other,
  List<int> pairs,
  List<int> otherPairs,
  List<bool> ambiguous,
  List<bool> otherAmbiguous,
) {
  return [
    for (final unit in reading.units)
      (() {
        var uncertain = unit.uncertain || unit.start == unit.end;
        var different = false;
        var unambiguousSubstitution = false;
        var unresolved = unit.unresolved;
        for (var i = unit.start; i < unit.end; i++) {
          final paired = pairs[i];
          final label = reading.phones[i];
          if (ambiguous[i]) unresolved = true;
          if (!_known(label)) {
            uncertain = true;
          } else if (paired < 0) {
            if (reading.wordBoundaryPhones.contains(i)) {
              uncertain = true;
            } else {
              different = true;
            }
          } else {
            final counterpart = other.units[other.owners[paired]];
            if (otherAmbiguous[paired] || counterpart.unresolved)
              unresolved = true;
            for (
              var token = counterpart.start;
              token < counterpart.end;
              token++
            ) {
              if (otherAmbiguous[token]) unresolved = true;
              if (otherPairs[token] < 0 && _known(other.phones[token])) {
                if (other.wordBoundaryPhones.contains(token)) {
                  uncertain = true;
                } else {
                  different = true;
                }
              }
            }
            if (!_known(other.phones[paired])) {
              uncertain = true;
            } else if (label != other.phones[paired]) {
              if (reading.wordBoundaryPhones.contains(i) ||
                  other.wordBoundaryPhones.contains(paired)) {
                uncertain = true;
              } else {
                different = true;
                unambiguousSubstitution =
                    unambiguousSubstitution ||
                    (!ambiguous[i] && !otherAmbiguous[paired]);
              }
            } else if (_merged.containsKey(label)) {
              uncertain = true;
            }
          }
        }
        if (unambiguousSubstitution) return ComparisonMark.different;
        if (unresolved) return ComparisonMark.uncertain;
        if (different) return ComparisonMark.different;
        return uncertain ? ComparisonMark.uncertain : ComparisonMark.match;
      })(),
  ];
}
