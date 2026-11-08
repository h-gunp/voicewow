import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/features/pronunciation/domain/pronunciation_comparison.dart';
import 'package:voicemate/features/pronunciation/domain/pronunciation_guide.dart';

void main() {
  // NIKL, Standard Pronunciation article 15 and inflected forms:
  // https://www.korean.go.kr/front/onlineQna/onlineQnaView.do?qna_seq=324749
  // https://www.korean.go.kr/front/onlineQna/onlineQnaView.do?qna_seq=324340
  // https://www.korean.go.kr/front/onlineQna/onlineQnaView.do?qna_seq=335997
  // https://www.korean.go.kr/front/onlineQna/onlineQnaView.do?qna_seq=332200
  const examples = {
    '맛있다': ['마싣따', '마딛따'],
    '맛있어': ['마시써', '마디써'],
    '맛있어요': ['마시써요', '마디써요'],
    '맛있는': ['마신는', '마딘는'],
    '맛있게': ['마싣께', '마딛께'],
    '맛있습니다': ['마싣씀니다', '마딛씀니다'],
    '멋있다': ['머싣따', '머딛따'],
  };
  for (final example in examples.entries) {
    test('${example.key} accepts both standard readings', () {
      final reading = const PronunciationGuideEngine()
          .analyze(example.key)
          .pronunciation;
      expect(
        pronunciationReferences(example.key, reading),
        unorderedEquals(example.value),
      );
      expect(
        pronunciationReferences(example.key, example.value.last),
        unorderedEquals(example.value),
      );
    });
  }

  test('each occurrence varies independently and keeps punctuation', () {
    expect(
      pronunciationReferences('맛있어, 멋있다!', '마시써, 머싣따!'),
      unorderedEquals(['마시써, 머싣따!', '마디써, 머싣따!', '마시써, 머딛따!', '마디써, 머딛따!']),
    );
  });

  test('only the source stem can authorize an alternate reading', () {
    expect(pronunciationReferences('마시다', '마시다'), ['마시다']);
    expect(pronunciationReferences('마싣께', '마싣께'), ['마싣께']);
    expect(pronunciationReferences('맛 있다', '마 시따'), ['마 시따']);
    expect(pronunciationReferences('맛있어', '마씨써'), ['마씨써']);
    expect(pronunciationReferences('맛있어', '마시써요'), ['마시써요']);
    expect(pronunciationReferences('🙂 맛있어? 마시다.', '🙂 마시써? 마시다.'), [
      '🙂 마시써? 마시다.',
      '🙂 마디써? 마시다.',
    ]);
  });

  test(
    'repeated stems keep original and all-changed readings within the cap',
    () {
      final original = List.filled(5, '맛있어').join(' ');
      final reading = List.filled(5, '마시써').join(' ');
      final variants = pronunciationReferences(original, reading);
      expect(variants.length, 16);
      expect(variants.first, reading);
      expect(variants, contains(List.filled(5, '마디써').join(' ')));
      expect(variants.toSet().length, variants.length);
    },
  );

  test(
    'valid alternate is not a difference and observed phones stay intact',
    () {
      final phones = 'M A D I SS EO'.split(' ');
      final result = comparePronunciation(
        phones: phones,
        references: pronunciationReferences('맛있어', '마시써'),
      );
      expect(result.reference, '마디써');
      expect(result.observed.map((span) => span.text).join(), '마디써');
      expect(result.differences, isEmpty);
      expect(phones, 'M A D I SS EO'.split(' '));
    },
  );

  test(
    'alternate reference preserves uncertain vowels and real differences',
    () {
      final references = pronunciationReferences('맛있게', '마싣께');
      final valid = comparePronunciation(
        phones: 'M A D I t GG E'.split(' '),
        references: references,
      );
      expect(valid.differences, isEmpty);
      expect(valid.observed.last.mark, ComparisonMark.uncertain);
      final changed = comparePronunciation(
        phones: 'M A D I t DD E'.split(' '),
        references: references,
      );
      expect(changed.observed.map((span) => span.text).join(), '마딛떼');
      expect(changed.observed.last.mark, ComparisonMark.different);
    },
  );
}
