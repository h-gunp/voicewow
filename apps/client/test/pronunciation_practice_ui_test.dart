import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/app_theme.dart';
import 'package:voicemate/app.dart';
import 'package:voicemate/features/pronunciation/data/learning_store.dart';
import 'package:voicemate/features/pronunciation/domain/quiz_catalog.dart';
import 'fake_audio_port.dart';
import 'package:voicemate/features/pronunciation/data/pronunciation_recorder_contract.dart';
import 'package:voicemate/features/pronunciation/data/speech_player.dart';
import 'package:voicemate/features/pronunciation/presentation/pronunciation_practice_view.dart';
import 'package:voicemate/features/pronunciation/presentation/speech_controls.dart';

class FakePronunciationRecorder implements PronunciationRecorder {
  int prepares = 0, starts = 0, finishes = 0, cancels = 0, plays = 0;
  Completer<List<String>>? pending;
  Completer<void>? startPending;
  String? failure;
  String? playbackFailure;
  void Function()? limit;
  List<String> phones = [
    'M',
    'A',
    'D',
    'I',
    't',
    'DD',
    'E',
    'M',
    'EO',
    'G',
    'EO',
    'DD',
    'EO',
  ];
  @override
  Future<void> prepare({void Function(String)? onProgress}) async {
    prepares++;
    onProgress?.call('모델 준비 중');
    if (failure != null) throw StateError(failure!);
  }

  @override
  Future<void> start({
    required void Function() onLimit,
    required void Function(String) onError,
  }) async {
    starts++;
    limit = onLimit;
    await startPending?.future;
  }

  @override
  Future<List<String>> finish() async {
    finishes++;
    return pending == null ? phones : await pending!.future;
  }

  @override
  Future<void> play() async {
    plays++;
    if (playbackFailure != null) throw StateError(playbackFailure!);
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }

  @override
  Future<void> dispose() async {}
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

Future<void> pumpPractice(
  WidgetTester tester,
  FakePronunciationRecorder recorder, {
  TextScaler? scaler,
}) async {
  final playback = SpeechPlaybackController(_SilentSpeech());
  addTearDown(playback.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            textScaler: scaler ?? TextScaler.noScaling,
          ),
          child: PronunciationPracticeView(
            text: '맛있게 먹었어',
            references: const ['마딛께 머거써', '마싣께 머거써'],
            recorder: recorder,
            playback: playback,
            onExit: () async {},
          ),
        ),
      ),
    ),
  );
}

Future<void> tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
}

void main() {
  testWidgets(
    'catalog detail cancels analysis on feature exit and never changes past answers',
    (tester) async {
      final recorder = FakePronunciationRecorder()
        ..pending = Completer<List<String>>();
      final learning = LearningController(
        MemoryLearningStore(
          LearningSnapshot(
            answers: {quizCatalog.first.id: false},
            wrongIds: {quizCatalog.first.id},
          ),
        ),
      );
      addTearDown(learning.dispose);
      await tester.pumpWidget(
        VoiceMateApp(
          audioPort: FakeAudioPort(),
          pronunciationLearning: learning,
          pronunciationSpeech: _SilentSpeech(),
          pronunciationRecorder: recorder,
          startWithPronunciation: true,
        ),
      );
      await tester.pumpAndSettle();
      for (final key in [
        'category-words',
        'quiz-group-words-0',
        'quiz-item-${quizCatalog.first.id}',
      ]) {
        await tap(tester, key);
        await tester.pumpAndSettle();
      }
      expect(find.text(quizCatalog.first.text), findsOneWidget);
      await tap(tester, 'pronunciation-bookmark');
      await tap(tester, 'pronunciation-prepare');
      await tester.pumpAndSettle();
      await tap(tester, 'pronunciation-mic');
      await tap(tester, 'pronunciation-mic');
      final before = recorder.cancels;
      await tester.tap(find.widgetWithText(NavigationDestination, '음량 측정'));
      await tester.pumpAndSettle();
      expect(find.byType(PronunciationPracticeView), findsNothing);
      expect(recorder.cancels, greaterThan(before));
      recorder.pending!.complete(recorder.phones);
      await tester.pumpAndSettle();
      expect(learning.answers, {quizCatalog.first.id: false});
      expect(learning.wrongIds, {quizCatalog.first.id});
      expect(learning.bookmarkedIds, contains(quizCatalog.first.id));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'personal guide opens recording and back cancels a pending microphone start',
    (tester) async {
      final recorder = FakePronunciationRecorder()
        ..startPending = Completer<void>();
      final learning = LearningController(MemoryLearningStore());
      addTearDown(learning.dispose);
      await tester.pumpWidget(
        VoiceMateApp(
          audioPort: FakeAudioPort(),
          pronunciationLearning: learning,
          pronunciationSpeech: _SilentSpeech(),
          pronunciationRecorder: recorder,
          startWithPronunciation: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, '내 문장'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, '같이 가요'));
      await tester.pumpAndSettle();
      await tap(tester, 'guide-practice');
      await tester.pumpAndSettle();
      expect(find.text('가치 가요'), findsOneWidget);
      await tap(tester, 'pronunciation-prepare');
      await tester.pumpAndSettle();
      await tap(tester, 'pronunciation-mic');
      final before = recorder.cancels;
      await tap(tester, 'pronunciation-back');
      await tester.pumpAndSettle();
      recorder.startPending!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(PronunciationPracticeView), findsNothing);
      expect(recorder.cancels, greaterThan(before));
      expect(find.byKey(const Key('guide-input')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'prepare is explicit and one microphone button starts and finishes before showing comparisons',
    (tester) async {
      final recorder = FakePronunciationRecorder();
      await pumpPractice(tester, recorder);
      expect(recorder.prepares, 0);
      await tap(tester, 'pronunciation-prepare');
      await tester.pumpAndSettle();
      await tap(tester, 'pronunciation-mic');
      expect(recorder.starts, 1);
      await tap(tester, 'pronunciation-mic');
      await tester.pumpAndSettle();
      expect(recorder.finishes, 1);
      expect(find.byKey(const Key('pronunciation-observed')), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('색은 추정'), 180);
      expect(find.textContaining('추정'), findsWidgets);
      expect(find.byKey(const Key('quiz-submit')), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const Key('pronunciation-replay')),
        180,
      );
      await tap(tester, 'pronunciation-replay');
      await tester.pumpAndSettle();
      expect(recorder.plays, 1);
    },
  );

  testWidgets(
    'playback failure clears discarded recording before model preparation retry',
    (tester) async {
      final recorder = FakePronunciationRecorder()
        ..playbackFailure = '녹음을 재생하지 못했다.';
      await pumpPractice(tester, recorder);
      await tap(tester, 'pronunciation-prepare');
      await tester.pumpAndSettle();
      await tap(tester, 'pronunciation-mic');
      await tap(tester, 'pronunciation-mic');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('pronunciation-replay')),
        180,
      );
      await tap(tester, 'pronunciation-replay');
      await tester.pumpAndSettle();
      expect(recorder.cancels, 1);
      expect(find.byKey(const Key('pronunciation-replay')), findsNothing);
      expect(find.byKey(const Key('pronunciation-observed')), findsNothing);
      await tap(tester, 'pronunciation-prepare');
      await tester.pumpAndSettle();
      expect(recorder.prepares, 2);
      expect(find.byKey(const Key('pronunciation-replay')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disposed view cancels pending recognition and ignores its late result',
    (tester) async {
      final recorder = FakePronunciationRecorder()
        ..pending = Completer<List<String>>();
      await pumpPractice(tester, recorder);
      await tap(tester, 'pronunciation-prepare');
      await tester.pumpAndSettle();
      await tap(tester, 'pronunciation-mic');
      await tap(tester, 'pronunciation-mic');
      await tester.pumpWidget(const SizedBox());
      recorder.pending!.complete(recorder.phones);
      await tester.pumpAndSettle();
      expect(recorder.cancels, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'automatic limit finalizes once and 200 percent text remains usable at 320px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 680);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final recorder = FakePronunciationRecorder();
      await pumpPractice(tester, recorder, scaler: TextScaler.linear(2));
      await tap(tester, 'pronunciation-prepare');
      await tester.pumpAndSettle();
      await tap(tester, 'pronunciation-mic');
      recorder.limit!();
      recorder.limit!();
      await tester.pumpAndSettle();
      expect(recorder.finishes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('model failure allows retry without requesting a microphone', (
    tester,
  ) async {
    final recorder = FakePronunciationRecorder()..failure = '모델을 준비하지 못했다.';
    await pumpPractice(tester, recorder);
    await tap(tester, 'pronunciation-prepare');
    await tester.pumpAndSettle();
    expect(find.textContaining('모델을 준비하지 못했다.'), findsOneWidget);
    expect(recorder.starts, 0);
    recorder.failure = null;
    await tap(tester, 'pronunciation-prepare');
    await tester.pumpAndSettle();
    expect(recorder.prepares, 2);
  });
}
