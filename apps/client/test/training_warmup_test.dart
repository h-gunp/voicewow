import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/app.dart';
import 'package:voicemate/features/pronunciation/data/learning_store.dart';
import 'package:voicemate/features/pronunciation/presentation/pronunciation_screen.dart';
import 'package:voicemate/features/prosody/presentation/prosody_screen.dart';
import 'package:voicemate/features/prosody/practice_session.dart';
import 'package:voicemate/screens/scenario_screen.dart';

import 'fake_audio_port.dart';

void main() {
  testWidgets('pronunciation entry completes warmup before mounting practice', (
    tester,
  ) async {
    final port = FakeAudioPort();
    final learning = LearningController(MemoryLearningStore());
    addTearDown(learning.dispose);
    await tester.pumpWidget(
      VoiceMateApp(
        audioPort: port,
        startWithPronunciation: true,
        pronunciationLearning: learning,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 / 3 · 자세 풀기'), findsOneWidget);
    expect(find.byType(PronunciationScreen), findsNothing);
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('1 / 3 · 자세 풀기'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('warmup-next')));
    await tester.tap(find.byKey(const Key('warmup-next')));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3 · 숨 들이마시기'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('warmup-previous')));
    await tester.tap(find.byKey(const Key('warmup-previous')));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3 · 자세 풀기'), findsOneWidget);
    for (var i = 0; i < 2; i++) {
      await tester.ensureVisible(find.byKey(const Key('warmup-next')));
      await tester.tap(find.byKey(const Key('warmup-next')));
      await tester.pumpAndSettle();
    }
    expect(find.text('3 / 3 · 숨 내쉬기'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('warmup-start')));
    await tester.tap(find.byKey(const Key('warmup-start')));
    await tester.pumpAndSettle();
    expect(find.byType(PronunciationScreen), findsOneWidget);
    expect(port.starts, 0);
    await tester.tap(find.byKey(const Key('open-training-guide')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PronunciationScreen), findsOneWidget);
    expect(find.byKey(const Key('warmup-skip')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('prosody warmup supports back, skip and a fresh feature visit', (
    tester,
  ) async {
    final port = FakeAudioPort();
    final practice = PracticeSession();
    addTearDown(practice.dispose);
    await tester.pumpWidget(
      VoiceMateApp(
        audioPort: port,
        prosodySession: practice,
        startWithProsody: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ProsodyScreen), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ScenarioScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-prosody')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('warmup-skip')));
    await tester.tap(find.byKey(const Key('warmup-skip')));
    await tester.pumpAndSettle();
    expect(find.byType(ProsodyScreen), findsOneWidget);
    expect(practice.recording, isFalse);
    expect(port.starts, 0);
    await tester.tap(find.widgetWithText(NavigationDestination, '음량 측정'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-prosody')));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3 · 자세 풀기'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('warmup controls remain reachable at 320px and triple text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      VoiceMateApp(
        audioPort: FakeAudioPort(),
        textScaler: const TextScaler.linear(3),
        startWithPronunciation: true,
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.ensureVisible(find.byKey(const Key('warmup-next')));
      await tester.ensureVisible(find.byKey(const Key('warmup-next')));
      await tester.tap(find.byKey(const Key('warmup-next')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('몸과 목을 편하게').hitTestable(), findsOneWidget);
    }
    await tester.ensureVisible(find.byKey(const Key('warmup-start')));
    expect(find.byKey(const Key('warmup-start')).hitTestable(), findsOneWidget);
    await tester.tap(find.widgetWithText(NavigationDestination, '음량 측정'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-pronunciation')));
    await tester.pumpAndSettle();
    expect(find.text('몸과 목을 편하게').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
