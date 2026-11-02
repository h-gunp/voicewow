/// A deliberately bounded, offline reading aid, not a dictionary or a speech
/// assessment. It applies common rules inside runs of Hangul syllables; it does
/// not infer morphemes, meanings, proper names, phrase boundaries, or prosody.
///
/// Rule references (National Institute of Korean Language):
/// - Articles 13 and 23, liaison and tensification:
///   https://www.korean.go.kr/front/onlineQna/onlineQnaView.do?qna_seq=323814
/// - Articles 12 and 18, aspiration and nasal assimilation:
///   https://www.korean.go.kr/front/onlineQna/onlineQnaView.do?qna_seq=326779
/// - Standard Pronunciation, articles 8–20 and 23–30, in 한국 어문 규정집:
///   https://www.korean.go.kr/common/download.do?c_file_name=1d66f826-df50-418d-a34f-2c38fa1fd45e_0.pdf&file_path=reportData&o_file_name=한국어문규정집.pdf
library;

class PronunciationPoint {
  final String before;
  final String after;
  final String explanation;

  const PronunciationPoint({
    required this.before,
    required this.after,
    required this.explanation,
  });
}

class GuideResult {
  final String original;
  final String pronunciation;
  final List<PronunciationPoint> points;
  final List<String> notes;

  GuideResult({
    required this.original,
    required this.pronunciation,
    required Iterable<PronunciationPoint> points,
    required Iterable<String> notes,
  }) : points = List.unmodifiable(points),
       notes = List.unmodifiable(notes);

  /// Standalone letters such as ㄱ and decomposed Jamo cannot be converted.
  bool get hasHangul => RegExp('[가-힣]').hasMatch(original);
}

class PronunciationGuideEngine {
  static const maxInputLength = 300;

  const PronunciationGuideEngine();

  /// Keeps whitespace, punctuation, numbers, and other scripts verbatim.
  /// Length is measured in Unicode code points, and input is never truncated.
  GuideResult analyze(String input) {
    if (input.runes.length > maxInputLength) {
      throw ArgumentError.value(
        input.runes.length,
        'input',
        '문장은 $maxInputLength자 이내로 입력해 주세요.',
      );
    }
    final notes = <String>{};
    final points = <PronunciationPoint>[];
    final pointKeys = <String>{};
    final hasHangul = RegExp('[가-힣]').hasMatch(input);

    if (!hasHangul) {
      notes.add('가·나처럼 완성된 한글 음절이 포함된 문장을 입력해 주세요.');
    } else {
      notes.add(
        '기본 발음 규칙과 일부 단어 예외를 적용한 참고 안내예요. '
        '뜻·단어의 구성·고유 명사에 따라 읽는 소리가 달라질 수 있어요.',
      );
      notes.add(
        '띄어쓰기와 문장부호를 경계로 나누어 안내해요. '
        '단어를 이어 읽을 때의 변화와 장단음·억양은 반영하지 않아요.',
      );
    }
    if (RegExp(r'[A-Za-z0-9]').hasMatch(input)) {
      notes.add('숫자와 영문은 읽는 말로 바꾸지 않고 입력한 그대로 표시해요.');
    }
    if (RegExp('[ㄱ-ㆎᄀ-ᇿ]').hasMatch(input)) {
      notes.add('따로 입력된 한글 자모는 합치거나 발음으로 바꾸지 않아요.');
    }

    final pronunciation = input.replaceAllMapped(RegExp('[가-힣]+'), (match) {
      final word = match.group(0)!;
      final ambiguous = _ambiguousWords.entries.where(
        (entry) => word.startsWith(entry.key),
      );
      if (ambiguous.isNotEmpty) {
        // Meaning changes the rule itself. Keeping these tokens is preferable
        // to presenting one guess as their unique pronunciation.
        notes.add(ambiguous.first.value);
        return word;
      }
      final converted = _convert(word);
      if (converted.text != word) {
        final key = '$word\u0000${converted.text}';
        if (pointKeys.add(key)) {
          points.add(
            PronunciationPoint(
              before: word,
              after: converted.text,
              explanation: converted.explanations.join(' '),
            ),
          );
        }
      }
      if (converted.dictionaryBoundary) {
        notes.add(
          '‘$word’에는 미리 확인한 단어의 구성에 따른 예외를 적용했어요. '
          '다른 뜻이나 이름으로 쓰였다면 사전에서 확인해 주세요.',
        );
      }
      return converted.text;
    });
    if (hasHangul && points.isEmpty) {
      notes.add(
        '지원하는 기본 규칙으로 바뀌는 부분을 찾지 못했어요. '
        '표기와 실제 발음이 항상 같다는 뜻은 아니에요.',
      );
    }
    return GuideResult(
      original: input,
      pronunciation: pronunciation,
      points: points,
      notes: notes,
    );
  }

  _Conversion _convert(String word) {
    final syllables = word.runes.map(_Syllable.fromRune).toList();
    final explanations = <String>{};
    var dictionaryBoundary = false;

    // These are limited lexical entries, not a general compound-word parser.
    // Preserve underlying final consonants elsewhere, so that inflections such
    // as 겉옷을 -> 거도슬 can still be handled by liaison.
    for (final entry in _lexicalPatches.entries) {
      var offset = word.indexOf(entry.key);
      while (offset >= 0) {
        for (var j = 0; j < entry.value.length; j++) {
          syllables[offset + j] = _Syllable.fromRune(entry.value.codeUnitAt(j));
        }
        explanations.add('미리 확인한 단어의 된소리·ㄴ/ㄹ 예외를 참고했어요.');
        dictionaryBoundary = true;
        offset = word.indexOf(entry.key, offset + entry.key.length);
      }
    }
    for (final entry in _semanticBoundaries.entries) {
      var offset = word.indexOf(entry.key);
      while (offset >= 0) {
        final at = offset + entry.value;
        syllables[at].finalConsonant = _plainFinal(
          syllables[at].finalConsonant,
        );
        explanations.add('이 단어의 결합 경계에서는 받침을 대표 소리로 바꿔 이어요.');
        dictionaryBoundary = true;
        offset = word.indexOf(entry.key, offset + entry.key.length);
      }
    }
    for (final entry in _nInsertion.entries) {
      var offset = word.indexOf(entry.key);
      while (offset >= 0) {
        syllables[offset + entry.value + 1].initial = _n;
        explanations.add('미리 확인한 합성어에서 뒤 음절에 ㄴ 소리를 덧붙여요.');
        dictionaryBoundary = true;
        offset = word.indexOf(entry.key, offset + entry.key.length);
      }
    }

    // Aspiration and liaison must see the underlying finals, before the
    // seven-final-sound simplification (꽃을 must become 꼬츨, not 꼬들).
    for (var i = 0; i < syllables.length - 1; i++) {
      final left = syllables[i];
      final right = syllables[i + 1];
      var coda = left.finalConsonant;
      if (coda == 0) continue;

      if (_hFinals.contains(coda)) {
        final remainder = coda == 6 ? 4 : (coda == 15 ? 8 : 0);
        final aspirated = _aspiratedInitial[right.initial];
        if (aspirated != null) {
          left.finalConsonant = remainder;
          right.initial = aspirated;
          explanations.add('받침의 ㅎ과 뒤의 자음을 합쳐 거센소리로 읽어요.');
          continue;
        }
        if (right.initial == _s) {
          left.finalConsonant = remainder;
          right.initial = _ss;
          explanations.add('받침의 ㅎ 뒤에 오는 ㅅ을 된소리로 읽어요.');
          continue;
        }
        if (right.initial == _silent) {
          left.finalConsonant = remainder;
          explanations.add('모음으로 이어지는 이 부분에서는 받침의 ㅎ을 소리 내지 않아요.');
          coda = remainder;
        } else if (right.initial == _n) {
          left.finalConsonant = remainder == 0 ? 4 : remainder;
          explanations.add('ㄴ 앞에서 받침의 ㅎ이 없어지거나 ㄴ 소리로 바뀌어요.');
          continue;
        }
      }

      if (right.initial == _h) {
        final parts = _beforeH[coda];
        if (parts != null) {
          left.finalConsonant = parts.$1;
          right.initial = parts.$2;
          if ((coda == 7 || coda == 25) && right.vowel == _i) {
            right.initial = _ch;
            explanations.add('ㄷ·ㅌ과 히가 만나는 이 부분을 ㅊ 소리로 읽어요.');
          } else {
            explanations.add('받침과 뒤의 ㅎ을 합쳐 거센소리로 읽어요.');
          }
          continue;
        }
      }

      if (right.initial == _silent && coda != 0 && coda != 21) {
        final parts = _liaison[coda];
        if (parts == null) continue;
        left.finalConsonant = parts.$1;
        right.initial = parts.$2;
        if (right.vowel == _i && (coda == 7 || coda == 25)) {
          right.initial = coda == 7 ? _j : _ch;
          explanations.add('ㄷ·ㅌ 받침과 이가 만나는 이 부분을 ㅈ·ㅊ 소리로 읽어요.');
        } else {
          explanations.add('모음 앞의 받침을 뒤 음절 첫소리로 이어 읽어요.');
        }
      }
    }

    for (var i = 0; i < syllables.length; i++) {
      final syllable = syllables[i];
      final coda = syllable.finalConsonant;
      final next = i + 1 < syllables.length ? syllables[i + 1] : null;
      if (coda == 9 &&
          next?.initial == _g &&
          _liquidBeforeG.contains(word[i])) {
        syllable.finalConsonant = 8;
        next!.initial = _gg;
        explanations.add('이 용언의 ㄺ 받침은 ㄱ 앞에서 ㄹ로, 뒤의 ㄱ은 ㄲ로 읽어요.');
        continue;
      }
      if (_stemClusterFinals.contains(coda) &&
          next != null &&
          _tenseAfterStem.containsKey(next.initial)) {
        next.initial = _tenseAfterStem[next.initial]!;
        explanations.add('이 겹받침 뒤에 이어지는 자음을 된소리로 읽어요.');
      }
      final isBilabialException =
          coda == 11 &&
          (word[i] == '밟' ||
              word.startsWith('넓죽', i) ||
              word.startsWith('넓둥글', i));
      final plain = isBilabialException ? 17 : _plainFinal(coda);
      if (plain != coda) {
        syllable.finalConsonant = plain;
        explanations.add('음절 끝이나 자음 앞의 받침을 대표 소리로 읽어요.');
      }
    }

    for (var i = 0; i < syllables.length - 1; i++) {
      final left = syllables[i];
      final right = syllables[i + 1];
      if (left.finalConsonant == 4 && right.initial == _r) {
        left.finalConsonant = 8;
        explanations.add('이 부분의 ㄴ과 ㄹ을 이어 ㄹ·ㄹ로 읽어요.');
      } else if (left.finalConsonant == 8 && right.initial == _n) {
        right.initial = _r;
        explanations.add('ㄹ 뒤의 ㄴ을 ㄹ 소리로 읽어요.');
      } else if (right.initial == _r &&
          const {1, 7, 16, 17, 21}.contains(left.finalConsonant)) {
        right.initial = _n;
        explanations.add('이 받침 뒤에 오는 ㄹ을 ㄴ 소리로 읽어요.');
      }
      if (right.initial == _n || right.initial == _m) {
        final nasal = const {1: 21, 7: 4, 17: 16}[left.finalConsonant];
        if (nasal != null) {
          left.finalConsonant = nasal;
          explanations.add('ㄴ·ㅁ 앞의 ㄱ·ㄷ·ㅂ 받침을 ㅇ·ㄴ·ㅁ 소리로 바꿔 읽어요.');
        }
      }
      if (const {1, 7, 17}.contains(left.finalConsonant)) {
        final tense = _tenseInitial[right.initial];
        if (tense != null) {
          right.initial = tense;
          explanations.add('ㄱ·ㄷ·ㅂ 받침 뒤의 예사소리를 된소리로 읽어요.');
        }
      }
    }
    return _Conversion(
      syllables.map((s) => s.text).join(),
      explanations,
      dictionaryBoundary,
    );
  }
}

class _Syllable {
  int initial;
  final int vowel;
  int finalConsonant;

  _Syllable(this.initial, this.vowel, this.finalConsonant);

  factory _Syllable.fromRune(int rune) {
    final value = rune - 0xac00;
    return _Syllable(value ~/ 588, (value % 588) ~/ 28, value % 28);
  }

  String get text =>
      String.fromCharCode(0xac00 + initial * 588 + vowel * 28 + finalConsonant);
}

class _Conversion {
  final String text;
  final Set<String> explanations;
  final bool dictionaryBoundary;

  _Conversion(this.text, this.explanations, this.dictionaryBoundary);
}

const _g = 0, _gg = 1, _n = 2, _r = 5, _m = 6, _s = 9, _ss = 10;
const _silent = 11, _j = 12, _ch = 14, _h = 18, _i = 20;
const _hFinals = {6, 15, 27};
const _stemClusterFinals = {5, 10, 11, 13};
const _liquidBeforeG = {'맑', '묽', '읽', '밝', '늙', '굵', '긁', '얽', '옭'};
const _aspiratedInitial = {0: 15, 3: 16, 12: 14};
const _tenseInitial = {0: 1, 3: 4, 7: 8, 9: 10, 12: 13};
const _tenseAfterStem = {0: 1, 3: 4, 9: 10, 12: 13};

int _plainFinal(int coda) => switch (coda) {
  2 || 3 || 9 || 24 => 1,
  5 || 6 => 4,
  11 || 12 || 13 || 15 => 8,
  10 => 16,
  14 || 18 || 26 => 17,
  19 || 20 || 22 || 23 || 25 || 27 => 7,
  _ => coda,
};

// (remaining final-consonant index, new initial-consonant index).
const _liaison = <int, (int, int)>{
  1: (0, 0),
  2: (0, 1),
  3: (1, 10),
  4: (0, 2),
  5: (4, 12),
  7: (0, 3),
  8: (0, 5),
  9: (8, 0),
  10: (8, 6),
  11: (8, 7),
  12: (8, 10),
  13: (8, 16),
  14: (8, 17),
  16: (0, 6),
  17: (0, 7),
  18: (17, 10),
  19: (0, 9),
  20: (0, 10),
  22: (0, 12),
  23: (0, 14),
  24: (0, 15),
  25: (0, 16),
  26: (0, 17),
};
const _beforeH = <int, (int, int)>{
  1: (0, 15),
  2: (0, 15),
  5: (4, 14),
  7: (0, 16),
  9: (8, 15),
  11: (8, 17),
  13: (8, 16),
  17: (0, 17),
  19: (0, 16),
  20: (0, 16),
  22: (0, 14),
  23: (0, 16),
  24: (0, 15),
  25: (0, 16),
  26: (0, 17),
};

// Distinguish independent morphemes in these checked words from the generic
// vowel-initial ending case. The boundary is the index of the left syllable.
const _semanticBoundaries = {
  '맛없': 0,
  '멋없': 0,
  '겉옷': 0,
  '홑옷': 0,
  '헛웃음': 0,
  '값어치': 0,
  '값있': 0,
};
const _nInsertion = {
  '꽃잎': 0,
  '깻잎': 0,
  '나뭇잎': 1,
  '솜이불': 0,
  '흙이불': 0,
  '막일': 0,
  '삯일': 0,
  '맨입': 0,
  '한여름': 0,
  '색연필': 0,
  '내복약': 1,
  '담요': 0,
  '눈요기': 0,
  '영업용': 1,
  '식용유': 1,
  '직행열차': 1,
  '서울역': 1,
  '물약': 0,
  '솔잎': 0,
  '불여우': 0,
  '앞일': 0,
  '뒷일': 0,
};

// Keep the same number of syllables and preserve finals needed by inflection.
const _lexicalPatches = {
  '의견란': '의견난',
  '임진란': '임진난',
  '생산량': '생산냥',
  '결단력': '결딴녁',
  '공권력': '공꿘녁',
  '동원령': '동원녕',
  '상견례': '상견녜',
  '횡단로': '횡단노',
  '이원론': '이원논',
  '임원료': '임원뇨',
  '구근류': '구근뉴',
  '문법': '문뻡',
};

// Do not choose among context-dependent readings without meaning analysis.
const _ambiguousWords = {
  '신고':
      '‘신고’는 알림을 뜻하는 말인지, 신발을 신는 동작인지에 따라 '
      '읽는 소리가 달라져 원문을 유지했어요. 문장 속 뜻을 확인해 주세요.',
  '안다':
      '‘안다’는 아는 것인지, 품에 안는 것인지에 따라 읽는 소리가 달라져 '
      '원문을 유지했어요. 문장 속 뜻을 확인해 주세요.',
  '신라면':
      '‘신라면’처럼 이름으로 쓰일 수 있는 말은 단어의 구성에 따라 발음이 '
      '달라질 수 있어 원문을 유지했어요. 해당 이름의 읽는 법을 확인해 주세요.',
  '밤일':
      '‘밤일’은 밤에 하는 일인지, ‘밤이다’의 활용인지에 따라 발음이 '
      '달라질 수 있어 원문을 유지했어요. 문장 속 뜻을 확인해 주세요.',
};
