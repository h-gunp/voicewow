import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/features/pronunciation/domain/ipa_phones.dart';
import 'package:voicemate/features/pronunciation/domain/pronunciation_comparison.dart';

void main() {
  PronunciationComparison compare(String ipa, String reference) =>
      comparePronunciation(
        phones: ipaToPhones(ipa.split(' ')),
        references: [reference],
      );
  test('actual IPA mispronunciations survive conversion and comparison', () {
    final result = compare('b a p m a d i t t* ɛ m ʌ ɡ ʌ t* ʌ', '밥마싣께머거써');
    expect(result.observed.map((s) => s.text).join(), '밥마딛떼머거떠');
    expect(
      result.observed.any((s) => s.mark == ComparisonMark.different),
      true,
    );
  });
  test(
    'voicing and positions preserve observed sequence; tense and aspirated differ',
    () {
      expect(
        ipaToPhones('k a ɡ a t a d a p a b a'.split(' ')),
        'G A G A D A D A B A B A'.split(' '),
      );
      expect(
        ipaToPhones('k* a t* a p* a tɕ* a s* a kʰ a'.split(' ')),
        'GG A DD A BB A JJ A SS A Kh A'.split(' '),
      );
      expect(
        compare('a n n jʌ ŋ', '안녕').observed.map((s) => s.text).join(),
        '안녕',
      );
      expect(compare('wʌ n', '원').observed.single.mark, ComparisonMark.match);
    },
  );
  test('unknown and merged vowels never become a match', () {
    expect(compare('ɛ', '에').observed.single.mark, ComparisonMark.uncertain);
    expect(
      compare('[UNK]', '아').observed.single.mark,
      ComparisonMark.uncertain,
    );
    expect(() => ipaToPhones(List.filled(1001, 'a')), throwsArgumentError);
  });
}
