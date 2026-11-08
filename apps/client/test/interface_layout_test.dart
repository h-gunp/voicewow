import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/app.dart';
import 'package:voicemate/features/pronunciation/data/learning_store.dart';
import 'package:voicemate/features/pronunciation/data/speech_player.dart';
import 'package:voicemate/features/prosody/practice_session.dart';
import 'fake_audio_port.dart';
import 'pronunciation_practice_ui_test.dart' show FakePronunciationRecorder;

void main() {
  testWidgets('desktop keeps the redesigned list and all three destinations', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(VoiceMateApp(audioPort: FakeAudioPort()));
    expect(
      tester.getSize(find.byKey(const Key('scenario-quiet'))).width,
      greaterThan(600),
    );
    expect(find.byType(NavigationDestination), findsNWidgets(3));
    expect(find.byKey(const Key('open-pronunciation')), findsOneWidget);
    expect(find.byKey(const Key('open-prosody')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'small enlarged layout retains quiz, sentences, review and prosody',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final learning = LearningController(MemoryLearningStore());
      final practice = PracticeSession();
      addTearDown(learning.dispose);
      addTearDown(practice.dispose);
      await tester.pumpWidget(
        VoiceMateApp(
          audioPort: FakeAudioPort(),
          textScaler: TextScaler.linear(2),
          pronunciationLearning: learning,
          pronunciationSpeech: _SilentSpeech(),
          pronunciationRecorder: FakePronunciationRecorder(),
          prosodySession: practice,
        ),
      );
      await tester.tap(find.byKey(const Key('open-pronunciation')));
      await tester.pumpAndSettle();
      expect(find.text('발음 연습'), findsOneWidget);
      expect(find.byKey(const Key('text-size-control')), findsOneWidget);
      await tester.ensureVisible(find.text('내 문장'));
      await tester.pumpAndSettle();
      expect(find.text('내 문장').hitTestable(), findsOneWidget);
      await tester.tap(find.text('내 문장'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guide-input')), findsOneWidget);
      await tester.ensureVisible(find.text('복습'));
      await tester.tap(find.text('복습'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-prosody')));
      await tester.pumpAndSettle();
      expect(find.text('연습 준비'), findsOneWidget);
      expect(find.byKey(const Key('text-size-control')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _SilentSpeech implements SpeechPlayer {
  @override
  Future<SpeechResult> speak(String text, {bool slow = false}) async =>
      SpeechResult.unavailable;
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
