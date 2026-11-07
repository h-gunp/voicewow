import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/app_theme.dart';
import 'package:voicemate/features/pronunciation/data/learning_store.dart';
import 'package:voicemate/features/pronunciation/domain/quiz_catalog.dart';
import 'package:voicemate/features/pronunciation/presentation/quiz_training_view.dart';

Future<void> tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'category and group choose a speaking target without writing a quiz answer',
    (tester) async {
      final learning = LearningController(MemoryLearningStore());
      await learning.load();
      addTearDown(learning.dispose);
      final selected = <QuizItem>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: QuizTrainingView(
              learning: learning,
              onPractice: selected.add,
            ),
          ),
        ),
      );
      final first = quizCatalog.first;
      await tap(tester, ValueKey('category-${first.category.name}'));
      await tap(tester, const Key('quiz-group-words-0'));
      await tap(tester, ValueKey('quiz-item-${first.id}'));
      expect(selected, [first]);
      expect(learning.answers, isEmpty);
      expect(find.byKey(const Key('quiz-submit')), findsNothing);
      await tap(tester, ValueKey('practice-bookmark-${first.id}'));
      expect(learning.bookmarkedIds, contains(first.id));
      expect(learning.answers, isEmpty);
    },
  );

  testWidgets(
    'review keeps past quiz history and opens bookmarked or saved speaking targets',
    (tester) async {
      final learning = LearningController(MemoryLearningStore());
      await learning.load();
      await learning.recordAnswer(quizCatalog.first.id, false);
      await learning.saveGuide('밥 맛있게 먹었어?');
      addTearDown(learning.dispose);
      final selected = <QuizItem>[], guides = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: QuizTrainingView(
              learning: learning,
              onPractice: selected.add,
              onOpenGuide: guides.add,
              reviewOnly: true,
            ),
          ),
        ),
      );
      await tap(tester, ValueKey('quiz-item-${quizCatalog.first.id}'));
      expect(selected.single.id, quizCatalog.first.id);
      await tap(tester, const Key('review-guide-밥 맛있게 먹었어?'));
      expect(guides, ['밥 맛있게 먹었어?']);
      expect(learning.answers[quizCatalog.first.id], false);
      await tap(tester, const Key('review-guide-delete-밥 맛있게 먹었어?'));
      expect(learning.guides, isEmpty);
      expect(learning.wrongIds, contains(quizCatalog.first.id));
    },
  );

  testWidgets(
    '320px enlarged catalog can choose a category and return without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 680);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final learning = LearningController(MemoryLearningStore());
      await learning.load();
      addTearDown(learning.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(2)),
              child: QuizTrainingView(learning: learning, onPractice: (_) {}),
            ),
          ),
        ),
      );
      await tap(tester, const Key('category-words'));
      await tap(tester, const Key('practice-catalog-back'));
      expect(find.byKey(const Key('category-words')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
