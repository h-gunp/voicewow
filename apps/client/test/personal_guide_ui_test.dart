import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/app_theme.dart';
import 'package:voicemate/features/pronunciation/data/learning_store.dart';
import 'package:voicemate/features/pronunciation/data/speech_player.dart';
import 'package:voicemate/features/pronunciation/presentation/pronunciation_screen.dart';

class FakeSpeech implements SpeechPlayer {
  final List<String> spoken = [];
  bool available = true;
  int stops = 0;
  @override
  Future<SpeechResult> speak(String text, {bool slow = false}) async {
    spoken.add(text);
    return available ? SpeechResult.started : SpeechResult.unavailable;
  }

  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> dispose() async {}
}

void main() {
  Future<void> open(
    WidgetTester tester,
    LearningController learning,
    FakeSpeech speech, {
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: PronunciationScreen(learning: learning, speech: speech),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('내 문장'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'personal sentence analyze, save, reload and stale result clear',
    (tester) async {
      final store = MemoryLearningStore();
      final learning = LearningController(store);
      final speech = FakeSpeech();
      await open(tester, learning, speech);
      await tester.tap(find.byKey(const Key('guide-analyze')));
      await tester.pumpAndSettle();
      expect(find.text('연습할 문장을 입력해 주세요.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('guide-input')), '같이 가요');
      await tester.tap(find.byKey(const Key('guide-analyze')));
      await tester.pumpAndSettle();
      expect(find.text('[가치 가요]'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('guide-save')));
      await tester.tap(find.byKey(const Key('guide-save')));
      await tester.pumpAndSettle();
      expect(store.value.guides.single.text, '같이 가요');
      final reload = LearningController(store);
      await reload.load();
      expect(reload.guides.single.text, '같이 가요');
      await tester.ensureVisible(find.byKey(const Key('guide-input')));
      await tester.enterText(find.byKey(const Key('guide-input')), 'hello');
      await tester.pump();
      expect(find.byKey(const Key('guide-result')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('guide-analyze')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('guide-analyze')));
      await tester.pumpAndSettle();
      expect(find.text('한글이 포함된 문장을 입력해 주세요.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      learning.dispose();
      reload.dispose();
    },
  );

  testWidgets('unavailable voice shows useful message, text guide remains', (
    tester,
  ) async {
    final learning = LearningController(MemoryLearningStore());
    final speech = FakeSpeech()..available = false;
    await open(tester, learning, speech);
    await tester.enterText(find.byKey(const Key('guide-input')), '같이 가요');
    await tester.tap(find.byKey(const Key('guide-analyze')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('예시 음성 듣기'));
    await tester.tap(find.text('예시 음성 듣기'));
    await tester.pumpAndSettle();
    expect(speech.spoken, ['같이 가요']);
    expect(find.textContaining('한국어 예시 음성을 재생할 수 없어요'), findsOneWidget);
    expect(find.byKey(const Key('guide-result')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    learning.dispose();
  });

  testWidgets('guide works at phone width with doubled text', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final learning = LearningController(MemoryLearningStore());
    await open(tester, learning, FakeSpeech(), scale: 2);
    await tester.enterText(find.byKey(const Key('guide-input')), '국물이 뜨거워요');
    await tester.ensureVisible(find.byKey(const Key('guide-analyze')));
    await tester.tap(find.byKey(const Key('guide-analyze')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('guide-save')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    learning.dispose();
  });
}
