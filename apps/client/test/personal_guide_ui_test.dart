import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/app.dart';
import 'package:voicemate/app_theme.dart';
import 'package:voicemate/features/pronunciation/data/learning_store.dart';
import 'package:voicemate/features/pronunciation/data/speech_player.dart';
import 'package:voicemate/features/pronunciation/presentation/pronunciation_screen.dart';
import 'fake_audio_port.dart';
import 'pronunciation_practice_ui_test.dart' show FakePronunciationRecorder;

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

class StatefulFakeSpeech extends FakeSpeech implements SpeechPlaybackSource {
  @override
  final ValueNotifier<SpeechPlaybackState> playback = ValueNotifier(
    const SpeechPlaybackState(),
  );
  Completer<SpeechResult>? pending;
  int requestId = 0;
  bool? lastSlow;

  @override
  Future<SpeechResult> speak(String text, {bool slow = false}) {
    spoken.add(text);
    lastSlow = slow;
    pending = Completer<SpeechResult>();
    playback.value = SpeechPlaybackState(
      phase: SpeechPhase.preparing,
      requestId: ++requestId,
    );
    return pending!.future;
  }

  void started() {
    playback.value = SpeechPlaybackState(
      phase: SpeechPhase.playing,
      requestId: requestId,
      result: SpeechResult.started,
    );
    pending?.complete(SpeechResult.started);
    pending = null;
  }

  void completed() {
    playback.value = SpeechPlaybackState(requestId: requestId);
  }

  @override
  Future<void> stop() async {
    stops++;
    if (pending != null && !pending!.isCompleted) {
      pending!.complete(SpeechResult.cancelled);
    }
    pending = null;
    playback.value = SpeechPlaybackState(
      requestId: requestId,
      result: SpeechResult.cancelled,
    );
  }
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
            body: PronunciationScreen(
              learning: learning,
              speech: speech,
              recorder: FakePronunciationRecorder(),
            ),
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
    for (final label in ['발음 연습', '내 문장', '복습']) {
      final text = find.descendant(
        of: find.widgetWithText(Tab, label),
        matching: find.text(label),
      );
      expect(
        tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
        isFalse,
        reason: label,
      );
    }
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

  testWidgets(
    'samples explain their action; saved guides reopen through review',
    (tester) async {
      final store = MemoryLearningStore(
        LearningSnapshot(
          answers: {'word-g-01': false},
          wrongIds: {'word-g-01'},
          bookmarkedIds: {'word-g-01'},
          guides: [SavedGuide('같이 가요', DateTime(2026, 11, 1))],
        ),
      );
      final learning = LearningController(store);
      await open(tester, learning, FakeSpeech());
      expect(find.text('예시 문장 · 눌러서 체험해 보세요'), findsOneWidget);
      await tester.tap(find.widgetWithText(ActionChip, '책을 읽어요'));
      await tester.pumpAndSettle();
      expect(find.text('[채글 일거요]'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('guide-save')));
      await tester.tap(find.byKey(const Key('guide-save')));
      await tester.pumpAndSettle();
      expect(store.value.guides.map((guide) => guide.text), [
        '책을 읽어요',
        '같이 가요',
      ]);

      Future<void> openSaved() async {
        await tester.ensureVisible(find.byKey(const Key('guide-open-saved')));
        await tester.tap(find.byKey(const Key('guide-open-saved')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ChoiceChip>(find.byKey(const Key('review-guides')))
              .selected,
          isTrue,
        );
      }

      await openSaved();
      await tester.ensureVisible(find.byKey(const Key('review-guide-같이 가요')));
      await tester.tap(find.byKey(const Key('review-guide-같이 가요')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pronunciation-prepare')), findsOneWidget);
      expect(find.text('같이 가요'), findsOneWidget);
      expect(find.text('가치 가요'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pronunciation-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, '내 문장'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('guide-input')))
            .controller!
            .text,
        '같이 가요',
      );
      expect(find.text('[가치 가요]'), findsOneWidget);

      await openSaved();
      await tester.tap(find.byKey(const Key('review-all')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ChoiceChip>(find.byKey(const Key('review-all'))).selected,
        isTrue,
      );
      await tester.tap(find.widgetWithText(Tab, '내 문장'));
      await tester.pumpAndSettle();
      await openSaved();
      await tester.ensureVisible(
        find.byKey(const Key('review-guide-delete-책을 읽어요')),
      );
      await tester.tap(find.byKey(const Key('review-guide-delete-책을 읽어요')));
      await tester.pumpAndSettle();
      final reload = LearningController(store);
      await reload.load();
      expect(reload.guides.single.text, '같이 가요');
      expect(reload.wrongIds, {'word-g-01'});
      expect(reload.bookmarkedIds, {'word-g-01'});
      expect(reload.answers['word-g-01'], isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      learning.dispose();
      reload.dispose();
    },
  );

  testWidgets(
    'personal speech shows preparation, actual playback, stop, and finish',
    (tester) async {
      final learning = LearningController(MemoryLearningStore());
      final speech = StatefulFakeSpeech();
      await open(tester, learning, speech);
      await tester.tap(find.widgetWithText(ActionChip, '같이 가요'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('guide-speak')));
      await tester.tap(find.byKey(const Key('guide-speak')));
      await tester.pump();
      expect(find.text('음성 준비 중…'), findsOneWidget);
      expect(find.text('재생 중 · 정지'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('guide-speak')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('guide-speak-slow')))
            .onPressed,
        isNull,
      );

      speech.started();
      await tester.pump();
      expect(find.text('재생 중 · 정지'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('guide-speak')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('guide-speak')));
      await tester.pumpAndSettle();
      expect(speech.stops, greaterThan(0));
      expect(find.text('재생 중 · 정지'), findsNothing);

      await tester.tap(find.byKey(const Key('guide-speak-slow')));
      await tester.pump();
      expect(speech.lastSlow, isTrue);
      speech.started();
      await tester.pump();
      speech.completed();
      await tester.pumpAndSettle();
      expect(find.text('재생 중 · 정지'), findsNothing);
      expect(find.text('음성 준비 중…'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('guide-speak-slow')))
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.byKey(const Key('guide-speak')));
      await tester.pump();
      final beforeSwitch = speech.stops;
      await tester.tap(find.widgetWithText(Tab, '복습'));
      await tester.pumpAndSettle();
      expect(speech.stops, greaterThan(beforeSwitch));
      expect(speech.playback.value.phase, SpeechPhase.ready);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      learning.dispose();
    },
  );

  testWidgets(
    'leaving the feature cancels speech and retains the same player on return',
    (tester) async {
      final learning = LearningController(MemoryLearningStore());
      final speech = StatefulFakeSpeech();
      await tester.pumpWidget(
        VoiceMateApp(
          audioPort: FakeAudioPort(),
          pronunciationLearning: learning,
          pronunciationSpeech: speech,
          pronunciationRecorder: FakePronunciationRecorder(),
          startWithPronunciation: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, '내 문장'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, '같이 가요'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('guide-speak')));
      await tester.tap(find.byKey(const Key('guide-speak')));
      await tester.pump();
      expect(speech.playback.value.phase, SpeechPhase.preparing);
      await tester.tap(find.widgetWithText(NavigationDestination, '음량 측정'));
      await tester.pumpAndSettle();
      expect(find.byType(PronunciationScreen), findsNothing);
      expect(speech.playback.value.phase, SpeechPhase.ready);

      await tester.tap(find.byKey(const Key('open-pronunciation')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PronunciationScreen>(find.byType(PronunciationScreen))
            .speech,
        same(speech),
      );
      await tester.tap(find.widgetWithText(Tab, '내 문장'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, '같이 가요'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('guide-speak')));
      await tester.tap(find.byKey(const Key('guide-speak')));
      await tester.pump();
      speech.started();
      await tester.pump();
      expect(find.text('재생 중 · 정지'), findsOneWidget);
      await tester.tap(find.byKey(const Key('guide-speak')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      learning.dispose();
    },
  );

  testWidgets('help keeps an unsaved personal sentence', (tester) async {
    final learning = LearningController(MemoryLearningStore());
    addTearDown(learning.dispose);
    await tester.pumpWidget(
      VoiceMateApp(
        audioPort: FakeAudioPort(),
        pronunciationLearning: learning,
        pronunciationSpeech: FakeSpeech(),
        pronunciationRecorder: FakePronunciationRecorder(),
        startWithPronunciation: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, '내 문장'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('guide-input')),
      '아직 저장하지 않은 문장',
    );
    await tester.tap(find.byKey(const Key('open-training-guide')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('guide-input')))
          .controller!
          .text,
      '아직 저장하지 않은 문장',
    );
    expect(learning.guides, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
