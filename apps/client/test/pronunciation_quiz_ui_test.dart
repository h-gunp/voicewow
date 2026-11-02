import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/app_theme.dart';
import 'package:voicemate/features/pronunciation/data/learning_store.dart';
import 'package:voicemate/features/pronunciation/domain/quiz_catalog.dart';
import 'package:voicemate/features/pronunciation/presentation/quiz_training_view.dart';

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets(
    'category and group journey records an answer only after checking it, then retries errors',
    (tester) async {
      final store = _CountingStore();
      final learning = LearningController(store);
      await learning.load();
      addTearDown(learning.dispose);
      final spoken = <String>[];
      await _pumpQuiz(tester, learning, spoken);

      for (final category in TrainingCategory.values) {
        expect(
          find.byKey(ValueKey('category-${category.name}')),
          findsOneWidget,
        );
      }
      final first = quizCatalog.first;
      final group = quizCatalog
          .where(
            (item) =>
                item.category == first.category && item.group == first.group,
          )
          .toList();
      await _tap(
        tester,
        find.byKey(ValueKey('category-${first.category.name}')),
      );
      await _tap(tester, find.widgetWithText(ChoiceChip, first.group));
      expect(find.byKey(ValueKey('quiz-item-${first.id}')), findsOneWidget);
      expect(
        find.byKey(
          ValueKey(
            'quiz-item-${quizCatalog.firstWhere((item) => item.group != first.group).id}',
          ),
        ),
        findsNothing,
      );
      await _tap(tester, find.byKey(ValueKey('quiz-item-${first.id}')));

      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('quiz-submit')))
            .onPressed,
        isNull,
      );
      expect(find.text(first.explanation), findsNothing);
      expect(find.text('A · 정답'), findsNothing);
      expect(find.text('B · 정답'), findsNothing);
      expect(find.byKey(const Key('quiz-speak')), findsNothing);
      expect(find.byKey(const Key('quiz-speak-slow')), findsNothing);
      expect(learning.answers, isEmpty);
      expect(spoken, isEmpty);

      final beforeBookmark = [_optionText(tester, 0), _optionText(tester, 1)];
      await _tap(tester, find.byKey(const Key('quiz-bookmark')));
      expect(learning.bookmarkedIds, contains(first.id));
      expect([_optionText(tester, 0), _optionText(tester, 1)], beforeBookmark);
      expect(learning.answers, isEmpty);

      await _tap(tester, find.text(_reading(first.distractor)));
      expect(learning.answers, isEmpty);
      expect(find.text(first.explanation), findsNothing);
      await _tap(tester, find.byKey(const Key('quiz-submit')));
      expect(learning.answers[first.id], isFalse);
      expect(learning.wrongIds, contains(first.id));
      expect(store.writes, 2); // One bookmark and one submitted answer.
      expect(find.text(first.explanation), findsOneWidget);
      expect(find.byKey(const Key('quiz-submit')), findsNothing);

      await _tap(tester, find.byKey(const Key('quiz-speak')));
      await _tap(tester, find.byKey(const Key('quiz-speak-slow')));
      expect(spoken, ['${first.text}|false', '${first.text}|true']);
      expect(store.writes, 2);
      await _tap(tester, find.byKey(const Key('quiz-next')));

      for (final item in group.skip(1)) {
        expect(find.text(item.text), findsOneWidget);
        await _tap(tester, find.text(_reading(item.pronunciation)));
        await _tap(tester, find.byKey(const Key('quiz-submit')));
        await _tap(tester, find.byKey(const Key('quiz-next')));
      }
      expect(find.byKey(const Key('quiz-summary')), findsOneWidget);
      expect(
        find.text('${group.length}문제 중 ${group.length - 1}문제 정답'),
        findsOneWidget,
      );

      await _tap(tester, find.byKey(const Key('quiz-retry-wrong')));
      expect(find.text('문제 1 / 1'), findsOneWidget);
      expect(find.text(first.text), findsOneWidget);
      await _tap(tester, find.text(_reading(first.pronunciation)));
      await _tap(tester, find.byKey(const Key('quiz-submit')));
      expect(learning.answers[first.id], isTrue);
      expect(learning.wrongIds, isNot(contains(first.id)));
      expect(learning.bookmarkedIds, contains(first.id));
      await _tap(tester, find.byKey(const Key('quiz-next')));
      expect(find.text('1문제 중 1문제 정답'), findsOneWidget);
      expect(find.byKey(const Key('quiz-retry-wrong')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'review separates saved problems and errors, and reflects a corrected answer',
    (tester) async {
      final wrong = quizCatalog.first;
      final saved = quizCatalog[1];
      final learning = LearningController(
        MemoryLearningStore(
          LearningSnapshot(
            answers: {wrong.id: false},
            wrongIds: {wrong.id},
            bookmarkedIds: {saved.id},
          ),
        ),
      );
      await learning.load();
      addTearDown(learning.dispose);
      await _pumpQuiz(tester, learning, <String>[], reviewOnly: true);

      expect(find.byKey(ValueKey('quiz-item-${wrong.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('quiz-item-${saved.id}')), findsNothing);
      await _tap(tester, find.byKey(const Key('review-bookmarks')));
      expect(find.byKey(ValueKey('quiz-item-${saved.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('quiz-item-${wrong.id}')), findsNothing);
      await _tap(tester, find.byTooltip('저장 해제'));
      expect(learning.bookmarkedIds, isEmpty);
      expect(find.text('저장한 문제가 아직 없어요'), findsOneWidget);

      await _tap(tester, find.byKey(const Key('review-wrong')));
      await _tap(tester, find.byKey(const Key('quiz-start-review')));
      await _tap(tester, find.text(_reading(wrong.pronunciation)));
      await _tap(tester, find.byKey(const Key('quiz-submit')));
      await _tap(tester, find.byKey(const Key('quiz-next')));
      await _tap(tester, find.text('목록으로 돌아가기'));
      expect(learning.wrongIds, isEmpty);
      expect(find.text('다시 볼 오답이 아직 없어요'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '320px and double text size remain usable through hub, list, answer, and summary',
    (tester) async {
      final item = quizCatalog.first;
      final learning = LearningController(
        MemoryLearningStore(LearningSnapshot(wrongIds: {item.id})),
      );
      await learning.load();
      addTearDown(learning.dispose);
      await _pumpQuiz(
        tester,
        learning,
        <String>[],
        size: const Size(320, 640),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      await _tap(tester, find.byKey(const Key('category-words')));
      expect(tester.takeException(), isNull);
      await _tap(tester, find.widgetWithText(ChoiceChip, item.group));
      await _tap(tester, find.byKey(ValueKey('quiz-item-${item.id}')));
      expect(tester.takeException(), isNull);
      await _tap(tester, find.text(_reading(item.pronunciation)));
      await _tap(tester, find.byKey(const Key('quiz-submit')));
      expect(tester.takeException(), isNull);
      await _tap(tester, find.byKey(const Key('quiz-speak-slow')));
      expect(tester.takeException(), isNull);

      // A one-question review also checks the completion screen at this size.
      await _pumpQuiz(
        tester,
        learning,
        <String>[],
        reviewOnly: true,
        size: const Size(320, 640),
        textScale: 2,
      );
      // The corrected item is gone from errors, but remains available when saved.
      expect(find.text('다시 볼 오답이 아직 없어요'), findsOneWidget);
      await learning.toggleBookmark(item.id);
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('review-bookmarks')));
      await _tap(tester, find.byKey(const Key('quiz-start-review')));
      await _tap(tester, find.text(_reading(item.pronunciation)));
      await _tap(tester, find.byKey(const Key('quiz-submit')));
      await _tap(tester, find.byKey(const Key('quiz-next')));
      expect(find.byKey(const Key('quiz-summary')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hardware back leaves the question before leaving its category', (
    tester,
  ) async {
    final learning = LearningController(MemoryLearningStore());
    await learning.load();
    addTearDown(learning.dispose);
    await _pumpQuiz(tester, learning, <String>[]);
    final first = quizCatalog.first;
    await _tap(tester, find.byKey(const Key('category-words')));
    await _tap(tester, find.byKey(ValueKey('quiz-item-${first.id}')));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quiz-submit')), findsNothing);
    expect(find.byKey(const Key('quiz-start-group')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('category-words')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpQuiz(
  WidgetTester tester,
  LearningController learning,
  List<String> spoken, {
  bool reviewOnly = false,
  Size size = const Size(1000, 900),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: QuizTrainingView(
          learning: learning,
          reviewOnly: reviewOnly,
          onSpeak: (text, slow) async => spoken.add('$text|$slow'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

String _optionText(WidgetTester tester, int index) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(ValueKey('quiz-option-$index')),
        matching: find.byType(Text),
      ),
    )
    .map((text) => text.data ?? '')
    .singleWhere((text) => text.startsWith('['));

String _reading(String value) => value.startsWith('[') ? value : '[$value]';

class _CountingStore extends MemoryLearningStore {
  int writes = 0;

  @override
  Future<void> save(LearningSnapshot value) async {
    writes++;
    await super.save(value);
  }
}
