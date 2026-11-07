import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/features/pronunciation/domain/pronunciation_comparison.dart';

PronunciationComparison compare(
  String phones,
  List<String> references, {
  bool approximate = false,
}) => comparePronunciation(
  phones: phones.isEmpty ? [] : phones.split(' '),
  references: references,
  referenceIsApproximate: approximate,
);

String textOf(List<PronunciationSpan> spans) =>
    spans.map((span) => span.text).join();

void main() {
  test(
    'keeps the observed utterance and locates known consonant differences',
    () {
      final result = compare('B A p M A D I t DD E M EO G EO DD EO', [
        '밥마딛께머거써',
        '밥마싣께머거써',
      ]);
      expect(textOf(result.observed), '밥마딛떼머거떠');
      expect(result.reference, '밥마딛께머거써');
      expect(result.observed[0].mark, ComparisonMark.match);
      expect(result.observed[3].mark, ComparisonMark.different);
      expect(result.observed.last.mark, ComparisonMark.different);
      expect(result.differences, contains('기준 께 → 인식 떼'));
      expect(result.differences, contains('기준 써 → 인식 떠'));
    },
  );

  test('selects the closest allowed surface pronunciation', () {
    final result = compare('M A S I t GG E', ['마딛께', '마싣께']);
    expect(result.reference, '마싣께');
    expect(textOf(result.observed), '마싣께');
    expect(result.differences, isEmpty);
    expect(result.observed.map((span) => span.mark), [
      ComparisonMark.match,
      ComparisonMark.match,
      ComparisonMark.uncertain,
    ]);
  });

  test('one omitted syllable does not shift the following comparison', () {
    final result = compare('G O J U', ['고다주']);
    expect(textOf(result.observed), '고주');
    expect(
      result.observed.every((span) => span.mark == ComparisonMark.match),
      isTrue,
    );
    expect(result.expected.map((span) => span.mark), [
      ComparisonMark.match,
      ComparisonMark.different,
      ComparisonMark.match,
    ]);
    expect(result.differences, contains('기준 다: 인식에서 누락'));
  });

  test('an extra syllable leaves later matching sounds aligned', () {
    final result = compare('G A H U J A', ['가자']);
    expect(textOf(result.observed), '가후자');
    expect(result.observed.map((span) => span.mark), [
      ComparisonMark.match,
      ComparisonMark.different,
      ComparisonMark.match,
    ]);
    expect(result.differences, contains('추가로 인식: 후'));
  });

  test('missing coda is compared within its syllable', () {
    final result = compare('B A G U', ['밥구']);
    expect(textOf(result.observed), '바구');
    expect(result.observed.first.mark, ComparisonMark.different);
    expect(result.observed.last.mark, ComparisonMark.match);
    expect(result.differences, contains('기준 밥 → 인식 바'));
  });

  test('known exact boundary phones match despite spacing and punctuation', () {
    final result = compare('B A p G U', ['밥 구!']);
    expect(textOf(result.expected), '밥 구!');
    expect(textOf(result.observed), '밥구');
    expect(result.differences, isEmpty);
    expect(
      result.observed.every((span) => span.mark == ComparisonMark.match),
      isTrue,
    );
  });

  test('a missing boundary coda does not defer the matching next syllable', () {
    final result = compare('B A G U', ['밥 구']);
    expect(result.observed.map((span) => span.mark), [
      ComparisonMark.uncertain,
      ComparisonMark.match,
    ]);
    expect(result.expected.first.mark, ComparisonMark.uncertain);
    expect(result.expected.last.mark, ComparisonMark.match);
    expect(result.differences, isEmpty);
  });

  test(
    'a known consonant difference inside a boundary syllable remains different',
    () {
      final result = compare('Ph A p G U', ['밥 구']);
      expect(result.observed.map((span) => span.mark), [
        ComparisonMark.different,
        ComparisonMark.match,
      ]);
      expect(result.differences, contains('기준 밥 → 인식 팝'));
    },
  );

  test(
    'catalog word boundaries defer assimilation but keep independent consonant differences',
    () {
      final boundary = compare('B A M M A G U', ['밥 마구']);
      expect(boundary.differences, isEmpty);
      expect(boundary.observed.first.mark, ComparisonMark.uncertain);
      final example = compare('B A p M A D I t DD E M EO G EO DD EO', [
        '밥 마딛께 머거써',
        '밥 마싣께 머거써',
      ], approximate: true);
      expect(textOf(example.observed), '밥마딛떼머거떠');
      expect(example.observed[3].mark, ComparisonMark.different);
      expect(example.observed.last.mark, ComparisonMark.different);
      expect(example.differences, contains('기준 께 → 인식 떼'));
    },
  );

  test('merged vowels never recover reference spelling or claim a match', () {
    for (final fixture in [
      ('G E', '개', '게'),
      ('iE', '얘', '예'),
      ('oE', '외', '웨'),
    ]) {
      final result = compare(fixture.$1, [fixture.$2]);
      expect(textOf(result.observed), fixture.$3);
      expect(result.observed.single.mark, ComparisonMark.uncertain);
      expect(result.expected.single.mark, ComparisonMark.uncertain);
      expect(result.differences, isEmpty);
    }
  });

  test('unmapped vowels and incomplete syllables remain visibly uncertain', () {
    final result = compare('B uEO [UNK] G', ['붜가']);
    expect(textOf(result.observed), 'ㅂ□□ㄱ');
    expect(
      result.observed.every((span) => span.mark == ComparisonMark.uncertain),
      isTrue,
    );
    expect(result.differences, isEmpty);
    expect(result.notes.any((note) => note.contains('uEO')), isTrue);
  });

  test('intervocalic nasal and liquid boundaries are not asserted', () {
    for (final phone in ['M', 'N', 'L', 'R']) {
      final result = compare('A $phone A', ['아나']);
      expect(
        result.observed.every((span) => span.mark == ComparisonMark.uncertain),
        isTrue,
      );
      expect(result.differences, isEmpty);
      expect(result.notes.any((note) => note.contains('경계')), isTrue);
    }
  });

  test('all equally optimal repeated-phone alignments are uncertain', () {
    final result = compare('G A G A', ['가가가']);
    expect(
      result.observed.every((span) => span.mark == ComparisonMark.uncertain),
      isTrue,
    );
    expect(
      result.expected.every((span) => span.mark == ComparisonMark.uncertain),
      isTrue,
    );
    expect(result.differences, isEmpty);
    expect(result.notes.any((note) => note.contains('정렬')), isTrue);
  });

  test(
    'equally close allowed references do not assert competing error locations',
    () {
      final result = compare('G A DD O', ['가도', '카또']);
      expect(
        result.observed.every((span) => span.mark == ComparisonMark.uncertain),
        isTrue,
      );
      expect(
        result.expected.every((span) => span.mark == ComparisonMark.uncertain),
        isTrue,
      );
      expect(result.differences, isEmpty);
      expect(result.notes.any((note) => note.contains('허용 기준')), isTrue);
    },
  );

  test('repeated-phone ambiguity stays local to the omitted region', () {
    final result = compare('G A J A', ['가다자']);
    expect(result.observed.first.mark, ComparisonMark.uncertain);
    expect(result.observed.last.mark, ComparisonMark.match);
    expect(result.expected.last.mark, ComparisonMark.match);
  });

  test('silence does not turn the reference into detected errors', () {
    final result = compare('', ['가다']);
    expect(result.observed, isEmpty);
    expect(
      result.expected.every((span) => span.mark == ComparisonMark.uncertain),
      isTrue,
    );
    expect(result.differences, isEmpty);
    expect(result.notes.any((note) => note.contains('음소가 없다')), isTrue);
  });

  test(
    'approximate references still permit experimental known-phone comparison',
    () {
      final result = compare('G A DD A', ['가다'], approximate: true);
      expect(result.observed.first.mark, ComparisonMark.match);
      expect(result.observed.last.mark, ComparisonMark.different);
      expect(result.notes.any((note) => note.contains('규칙 기반 참고')), isTrue);
    },
  );

  test(
    'approximate cross-word assimilation stays uncertain near the boundary',
    () {
      final result = compare('B A M M A G U', ['밥 마구'], approximate: true);
      expect(result.observed.first.mark, ComparisonMark.uncertain);
      expect(result.observed[1].mark, ComparisonMark.match);
      expect(result.observed.last.mark, ComparisonMark.match);
      expect(result.differences, isEmpty);
      expect(result.notes.any((note) => note.contains('어절')), isTrue);
    },
  );

  test(
    'unsupported reference characters are not accepted as pronunciation evidence',
    () {
      final result = compare('G A', ['ㄱA']);
      expect(
        result.expected.every((span) => span.mark == ComparisonMark.uncertain),
        isTrue,
      );
      expect(result.differences, isEmpty);
    },
  );

  test(
    'rejects malformed and excessive input before allocating alignment tables',
    () {
      for (final phones in [
        List.filled(1001, 'A'),
        [''],
        ['A' * 100],
      ]) {
        expect(
          () => comparePronunciation(phones: phones, references: ['가']),
          throwsArgumentError,
        );
      }
      for (final references in <List<String>>[
        [],
        [''],
        ['가' * 301],
        List.filled(17, '가'),
      ]) {
        expect(
          () => comparePronunciation(phones: ['A'], references: references),
          throwsArgumentError,
        );
      }
    },
  );
}
