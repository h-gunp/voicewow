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
  Completer<void>? playPending;
  String? failure;
  String? playbackFailure;
  void Function()? limit;
  void Function(String)? activity;
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
    void Function(String)? onVoiceActivity,
  }) async {
    starts++;
    limit = onLimit;
    activity = onVoiceActivity;
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
    await playPending?.future;
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
  if (find.byKey(Key(key)).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.byKey(Key(key)),
      100,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await Scrollable.ensureVisible(
    tester.element(find.byKey(Key(key))),
    alignment: .5,
  );
  await tester.pump();
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
}

void main() {
  testWidgets('recording progresses without voice activity classification', (
    tester,
  ) async {
    final recorder = FakePronunciationRecorder();
    await pumpPractice(tester, recorder);
    await tap(tester, 'pronunciation-prepare');
    await tester.pumpAndSettle();
    await tap(tester, 'pronunciation-mic');
    expect(recorder.activity, isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('읽고 나서 마이크를 다시 누르면 분석한다.'), findsOneWidget);
    expect(recorder.finishes, 0);
    await tap(tester, 'pronunciation-mic');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pronunciation-observed')), findsOneWidget);
    await tap(tester, 'pronunciation-mic');
    expect(recorder.activity, isNull);
    await tap(tester, 'pronunciation-cancel');
    await tester.pumpAndSettle();
    expect(find.text('중지했다. 모델 준비 후 다시 읽을 수 있다.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('help cancels pronunciation and keeps the practice reusable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final recorder = FakePronunciationRecorder();
    final learning = LearningController(MemoryLearningStore());
    addTearDown(learning.dispose);
    await tester.pumpWidget(
      VoiceMateApp(
        audioPort: FakeAudioPort(),
        pronunciationLearning: learning,
        pronunciationSpeech: _SilentSpeech(),
        pronunciationRecorder: recorder,
        startWithPronunciation: true,
        textScaler: const TextScaler.linear(3),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('warmup-skip')));
    await tester.tap(find.byKey(const Key('warmup-skip')));
    await tester.pumpAndSettle();
    for (final key in [
      'category-words',
      'quiz-group-words-0',
      'quiz-item-${quizCatalog.first.id}',
      'pronunciation-prepare',
      'pronunciation-mic',
    ]) {
      await tap(tester, key);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.byKey(const Key('pronunciation-cancel')));
    expect(
      find.byKey(const Key('pronunciation-cancel')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    final cancels = recorder.cancels;
    await tester.tap(find.byKey(const Key('open-training-guide')));
    await tester.pumpAndSettle();
    expect(recorder.cancels, greaterThan(cancels));
    expect(
      find.byType(PronunciationPracticeView, skipOffstage: false),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(quizCatalog.first.text), findsOneWidget);
    for (final key in ['pronunciation-prepare', 'pronunciation-mic']) {
      await tap(tester, key);
      await tester.pumpAndSettle();
    }
    expect(recorder.starts, 2);
    await tap(tester, 'pronunciation-mic');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pronunciation-observed')), findsOneWidget);
    final completedCancels = recorder.cancels;
    final prepares = recorder.prepares;
    await tester.tap(find.byKey(const Key('open-training-guide')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pronunciation-observed')), findsOneWidget);
    expect(find.byKey(const Key('pronunciation-prepare')), findsNothing);
    expect(recorder.cancels, completedCancels);
    expect(recorder.prepares, prepares);
    recorder.playPending = Completer<void>();
    await tap(tester, 'pronunciation-replay');
    await tester.tap(find.byKey(const Key('open-training-guide')));
    await tester.pumpAndSettle();
    recorder.playPending!.complete();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tap(tester, 'pronunciation-prepare');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pronunciation-observed')), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('pronunciation-replay')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

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
      await tester.ensureVisible(find.byKey(const Key('warmup-skip')));
      await tester.tap(find.byKey(const Key('warmup-skip')));
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
      await tester.ensureVisible(find.byKey(const Key('warmup-skip')));
      await tester.tap(find.byKey(const Key('warmup-skip')));
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
      await tester.scrollUntilVisible(find.textContaining('회색은 비교하기'), 180);
      expect(find.textContaining('회색은 비교하기 어려운 부분이다.'), findsOneWidget);
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
    'similar consonants use amber without changing the recognized pronunciation',
    (tester) async {
      final recorder = FakePronunciationRecorder()
        ..phones = [
          'M',
          'A',
          'D',
          'I',
          't',
          'GG',
          'E',
          'M',
          'EO',
          'GG',
          'EO',
          'SS',
          'EO',
        ];
      await pumpPractice(tester, recorder);
      await tap(tester, 'pronunciation-prepare');
      await tester.pumpAndSettle();
      await tap(tester, 'pronunciation-mic');
      await tap(tester, 'pronunciation-mic');
      await tester.pumpAndSettle();
      final observed = tester.widget<Text>(
        find.byKey(const Key('pronunciation-observed')),
      );
      final spans = (observed.textSpan! as TextSpan).children!.cast<TextSpan>();
      expect(spans.map((span) => span.text).join(), '마딛께머꺼써');
      final similar = spans.singleWhere((span) => span.text == '꺼');
      expect(similar.style!.color, const Color(0xff8a5a00));
      expect(similar.style!.decoration, isNull);
      expect(
        spans.singleWhere((span) => span.text == '마').style!.color,
        accent,
      );
      final expected = tester.widget<Text>(
        find.byKey(const Key('pronunciation-expected')),
      );
      final expectedSpans = (expected.textSpan! as TextSpan).children!
          .cast<TextSpan>();
      expect(
        expectedSpans.singleWhere((span) => span.text == '거').style!.color,
        const Color(0xff8a5a00),
      );
      await tester.scrollUntilVisible(find.text('≈ 비슷함'), 180);
      expect(
        tester.widget<Text>(find.text('≈ 비슷함')).style!.color,
        const Color(0xff8a5a00),
      );
      expect(find.text('… 불확실'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('기준 거 ↔ 인식 꺼: 비슷한 소리'), 180);
      expect(find.text('기준 거 ↔ 인식 꺼: 비슷한 소리'), findsOneWidget);
      expect(find.text('기준 거 → 인식 꺼'), findsNothing);
    },
  );

  testWidgets(
    'uncertain recognition keeps its gray color and legend without replacing its text',
    (tester) async {
      final recorder = FakePronunciationRecorder()
        ..phones = ['B', 'uEO', '[UNK]', 'G'];
      await pumpPractice(tester, recorder);
      await tap(tester, 'pronunciation-prepare');
      await tester.pumpAndSettle();
      await tap(tester, 'pronunciation-mic');
      await tap(tester, 'pronunciation-mic');
      await tester.pumpAndSettle();
      final observed = tester.widget<Text>(
        find.byKey(const Key('pronunciation-observed')),
      );
      final spans = (observed.textSpan! as TextSpan).children!.cast<TextSpan>();
      expect(spans.map((span) => span.text).join(), 'ㅂ□□ㄱ');
      expect(spans.every((span) => span.style!.color == muted), isTrue);
      final expected = tester.widget<Text>(
        find.byKey(const Key('pronunciation-expected')),
      );
      expect(
        (expected.textSpan! as TextSpan).children!.cast<TextSpan>().every(
          (span) => span.style!.color == muted,
        ),
        isTrue,
      );
      await tester.scrollUntilVisible(find.text('● 일치'), 180);
      expect(find.text('− 차이'), findsOneWidget);
      expect(find.text('… 불확실'), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('회색은 비교하기'), 180);
      expect(find.textContaining('불확실한 구간도 일치 색'), findsNothing);
      await tester.scrollUntilVisible(find.textContaining('uEO'), 180);
      expect(find.textContaining('uEO'), findsOneWidget);
    },
  );

  testWidgets(
    'known matches stay green and differences keep their red underline and explanation',
    (tester) async {
      final recorder = FakePronunciationRecorder();
      await pumpPractice(tester, recorder);
      await tap(tester, 'pronunciation-prepare');
      await tester.pumpAndSettle();
      await tap(tester, 'pronunciation-mic');
      await tap(tester, 'pronunciation-mic');
      await tester.pumpAndSettle();
      final observed = tester.widget<Text>(
        find.byKey(const Key('pronunciation-observed')),
      );
      final spans = (observed.textSpan! as TextSpan).children!.cast<TextSpan>();
      final match = spans.singleWhere((span) => span.text == '마');
      expect(match.style!.color, accent);
      expect(match.style!.decoration, isNull);
      for (final text in ['떼', '떠']) {
        final span = spans.singleWhere((span) => span.text == text);
        expect(span.style!.color, red);
        expect(span.style!.decoration, TextDecoration.underline);
      }
      await tester.scrollUntilVisible(find.text('기준 께 → 인식 떼'), 180);
      expect(find.text('기준 께 → 인식 떼'), findsOneWidget);
      expect(find.text('기준 써 → 인식 떠'), findsOneWidget);
    },
  );

  testWidgets(
    'empty recognition clears the result and permits another take without preparing again',
    (tester) async {
      final recorder = FakePronunciationRecorder();
      await pumpPractice(tester, recorder);
      await tap(tester, 'pronunciation-prepare');
      await tester.pumpAndSettle();
      await tap(tester, 'pronunciation-mic');
      await tap(tester, 'pronunciation-mic');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pronunciation-observed')), findsOneWidget);
      recorder.phones = [];
      await tap(tester, 'pronunciation-mic');
      await tap(tester, 'pronunciation-mic');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pronunciation-observed')), findsNothing);
      expect(find.byKey(const Key('pronunciation-expected')), findsNothing);
      expect(find.byKey(const Key('pronunciation-replay')), findsNothing);
      expect(find.textContaining('인식된 발음이 없다'), findsOneWidget);
      expect(find.byKey(const Key('pronunciation-prepare')), findsNothing);
      expect(recorder.prepares, 1);
      await tap(tester, 'pronunciation-mic');
      expect(recorder.starts, 3);
      expect(find.text('녹음 종료 · 분석'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
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
