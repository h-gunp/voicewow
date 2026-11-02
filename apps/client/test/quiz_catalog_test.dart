import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/features/pronunciation/domain/quiz_catalog.dart';
import 'package:voicemate/features/pronunciation/domain/pronunciation_guide.dart';

void main() {
  test(
    'personal guide agrees with independently curated practice readings',
    () {
      const engine = PronunciationGuideEngine();
      for (final item in quizCatalog) {
        expect(
          engine.analyze(item.text).pronunciation,
          item.pronunciation,
          reason: item.text,
        );
      }
    },
  );
  test('each agreed category has content and at least two usable groups', () {
    expect(TrainingCategory.values.map((category) => category.label), [
      '단어',
      '기초 문장',
      '확장 문장',
      '비즈니스 문장',
    ]);
    for (final category in TrainingCategory.values) {
      expect(
        quizCatalog.where((item) => item.category == category).length,
        greaterThanOrEqualTo(8),
        reason: category.label,
      );
      final groups = groupsForCategory(category);
      expect(groups.length, greaterThanOrEqualTo(2));
      for (final group in groups) {
        final items = itemsForGroup(category, group);
        expect(items, isNotEmpty);
        expect(items.every((item) => item.category == category), isTrue);
        expect(items.every((item) => item.group == group), isTrue);
      }
    }
  });

  test('question IDs remain unique so saved progress cannot collide', () {
    final ids = quizCatalog.map((item) => item.id).toSet();
    expect(ids.length, quizCatalog.length);
    expect(ids.every((id) => RegExp(r'^[a-z0-9-]+$').hasMatch(id)), isTrue);
  });

  test(
    'each question has a distinct wrong option, explanation, and official source',
    () {
      for (final item in quizCatalog) {
        expect(item.text.trim(), isNotEmpty, reason: item.id);
        expect(item.pronunciation.trim(), isNotEmpty, reason: item.id);
        expect(item.distractor.trim(), isNotEmpty, reason: item.id);
        expect(item.pronunciation, isNot(item.distractor), reason: item.id);
        expect(item.explanation.trim(), isNotEmpty, reason: item.id);
        final source = Uri.parse(item.sourceUrl);
        expect(source.scheme, 'https', reason: item.id);
        expect(
          source.host == 'korean.go.kr' ||
              source.host.endsWith('.korean.go.kr'),
          isTrue,
          reason: item.id,
        );
        // The UI adds brackets. Keeping options plain prevents nested brackets.
        expect(item.pronunciation.contains('['), isFalse, reason: item.id);
        expect(item.distractor.contains('['), isFalse, reason: item.id);
      }
    },
  );

  test(
    'independent sound-change anchors protect against content regressions',
    () {
      QuizItem word(String text) => quizCatalog.singleWhere(
        (item) => item.category == TrainingCategory.words && item.text == text,
      );
      expect(word('같이').pronunciation, '가치');
      expect(word('굳이').pronunciation, '구지');
      expect(word('국물').pronunciation, '궁물');
      expect(word('국밥').pronunciation, '국빱');
      expect(word('박수').pronunciation, '박쑤');
      expect(word('밥물').pronunciation, '밤물');
    },
  );

  test(
    'sentence exercises disclose the reading scope and filter unknown groups',
    () {
      expect(catalogReadingNote, contains('어절별'));
      expect(catalogReadingNote, contains('소리의 길이'));
      expect(itemsForGroup(TrainingCategory.words, '없는 분류'), isEmpty);
    },
  );
}
