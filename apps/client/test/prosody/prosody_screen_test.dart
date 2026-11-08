import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/app.dart';
import 'package:voicemate/features/prosody/audio/audio_analysis.dart';
import 'package:voicemate/features/prosody/practice_feedback.dart';
import 'package:voicemate/features/prosody/practice_session.dart';
import 'package:voicemate/features/prosody/presentation/prosody_screen.dart';
import 'package:voicemate/features/prosody/services/device_audio.dart';
import 'package:voicemate/features/prosody/widgets/prosody_chart.dart';

AudioAnalysis _analysis() => AudioAnalysis(
  duration: 1.2,
  frames: List.generate(
    61,
    (i) => AudioFrame(
      time: i * .02,
      pitchHz: (180 * math.pow(2, i * .08 / 12)).toDouble(),
      rmsDb: -20,
      active: true,
      relativePitch: i * .08,
      relativeDb: 0,
    ),
  ),
  pitchMedian: 205,
  voicedFrames: 61,
);

PracticeResult _accepted(AudioAnalysis reference) {
  final analysis = reference;
  final comparison = Comparison(
    path: List.generate(reference.frames.length, (i) => (i, i)),
    voicedPairs: reference.frames.length,
  );
  return PracticeResult(
    RecordedAudio(
      samples: const [],
      sampleRate: 16000,
      path: 'accepted.wav',
      bytes: Uint8List(0),
    ),
    analysis,
    comparison,
    buildPracticeSummary(reference, analysis, comparison),
    analysis.frames,
  );
}

class _ScreenAudio extends DeviceAudioService {
  int cancellations = 0, guideCancellations = 0;
  Completer<void>? cancellationGate, playbackStopGate;
  @override
  Stream<String> get errors => const Stream.empty();
  @override
  Future<void> cancel() async {
    cancellations++;
  }

  @override
  Future<void> cancelGuide() async {
    guideCancellations++;
    await cancellationGate?.future;
  }

  @override
  Future<void> stopPlayback() async {
    await playbackStopGate?.future;
  }

  @override
  Future<void> dispose() async {}
}

/// UI state fixtures deliberately do not claim to validate the audio pipeline.
class _ScreenSession extends PracticeSession {
  _ScreenSession() : super(audio: _ScreenAudio()) {
    reference = ReferenceClip('안녕하세요.', 'guide.wav', _analysis(), '한국어 예시');
  }
  bool failStop = false, failStart = false;
  int starts = 0, stops = 0;
  @override
  Future<void> startRecording() async {
    starts++;
    if (failStart) {
      phase = PracticePhase.idle;
      status = '마이크 권한을 확인해 주세요. 이전 결과는 보관했어요.';
    } else {
      phase = PracticePhase.recording;
      status = '주황 선을 보며 읽어 주세요.';
      liveTrace = _analysis().frames.take(20).toList();
      currentVoice = true;
    }
    notifyListeners();
  }

  @override
  Future<void> stopRecording() async {
    stops++;
    phase = PracticePhase.processing;
    notifyListeners();
    await Future<void>.value();
    if (failStop) {
      status = '목소리를 충분히 잡지 못했어요. 이전 결과는 보관했어요.';
    } else {
      result = _accepted(reference!.analysis);
      status = '녹음이 끝났어요.';
    }
    phase = PracticePhase.idle;
    notifyListeners();
  }

  @override
  Future<void> generateGuide() async {
    phase = PracticePhase.generating;
    status = '한국어 가이드를 만들고 있어요.';
    notifyListeners();
  }
}

Future<void> _mount(
  WidgetTester tester,
  _ScreenSession s, {
  double width = 390,
  double height = 844,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    VoiceMateApp(
      startWithProsody: true,
      prosodySession: s,
      textScaler: TextScaler.linear(scale),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _finish(WidgetTester tester, _ScreenSession s) async {
  await tester.pumpWidget(const SizedBox());
  s.dispose();
}

void main() {
  testWidgets(
    'suspending the screen stops audio without replacing its guide or accepted result',
    (tester) async {
      final s = _ScreenSession();
      final reference = s.reference;
      final accepted = _accepted(reference!.analysis);
      s.result = accepted;
      s.phase = PracticePhase.recording;
      Widget app(bool suspended) => MaterialApp(
        home: Scaffold(
          body: ProsodyScreen(session: s, suspended: suspended),
        ),
      );
      await tester.pumpWidget(app(false));
      await tester.pumpWidget(app(true));
      await tester.pumpAndSettle();
      final audio = s.audio as _ScreenAudio;
      expect(audio.cancellations, 1);
      expect(s.reference, same(reference));
      expect(s.result, same(accepted));
      await tester.pumpWidget(app(true));
      await tester.pumpAndSettle();
      expect(
        audio.cancellations,
        1,
        reason: 'unchanged suspension must not repeat cancellation',
      );
      await tester.pumpWidget(app(false));
      await tester.pumpAndSettle();
      expect(s.reference, same(reference));
      expect(s.result, same(accepted));
      await _finish(tester, s);
    },
  );

  testWidgets(
    'preparation, recorder and accepted results are separate views and recording is explicit',
    (tester) async {
      final s = _ScreenSession();
      await _mount(tester, s);
      expect(find.text('연습 준비'), findsOneWidget);
      expect(find.byType(ProsodyChart), findsNothing);
      expect(s.starts, 0);
      await tester.tap(find.byKey(const Key('prosody-prepare-next')));
      await tester.pumpAndSettle();
      expect(find.text('목소리 녹음'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      expect(find.byKey(const Key('prosody-script-input')), findsNothing);
      expect(find.byKey(const Key('prosody-practice-region')), findsNothing);
      expect(s.starts, 0);
      await tester.tap(find.byKey(const Key('prosody-record-toggle')));
      await tester.pumpAndSettle();
      expect(s.recording, isTrue);
      final live = tester.widget<ProsodyChart>(find.byType(ProsodyChart));
      expect(live.live, isTrue);
      expect(live.trace, same(s.liveTrace));
      await tester.tap(find.byKey(const Key('prosody-record-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('내 목소리 결과'), findsOneWidget);
      expect(find.byKey(const Key('prosody-record-toggle')), findsNothing);
      final chart = tester.widget<ProsodyChart>(find.byType(ProsodyChart));
      expect(chart.regions, same(s.result!.summary.segments));
      expect(chart.trace, same(s.result!.trace));
      await tester.scrollUntilVisible(
        find.text('이번 목소리'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('이번 목소리'), findsOneWidget);
      expect(find.text('다음엔 이렇게 해 봐요'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _finish(tester, s);
    },
  );

  testWidgets(
    'failed retry stays on recorder, preserves the accepted take and can reopen it',
    (tester) async {
      final s = _ScreenSession();
      final accepted = _accepted(s.reference!.analysis);
      s.result = accepted;
      await _mount(tester, s);
      await tester.tap(find.byKey(const Key('prosody-back')));
      await tester.pumpAndSettle();
      expect(find.text('목소리 녹음'), findsOneWidget);
      expect(
        tester.widget<ProsodyChart>(find.byType(ProsodyChart)).trace,
        isEmpty,
      );
      s.failStop = true;
      await tester.tap(find.byKey(const Key('prosody-record-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prosody-record-toggle')));
      await tester.pumpAndSettle();
      expect(s.result, same(accepted));
      expect(find.text('목소리 녹음'), findsOneWidget);
      expect(find.text('내 목소리 결과'), findsNothing);
      expect(
        tester.widget<ProsodyChart>(find.byType(ProsodyChart)).trace,
        isEmpty,
      );
      await tester.ensureVisible(
        find.byKey(const Key('prosody-previous-result')),
      );
      await tester.tap(find.byKey(const Key('prosody-previous-result')));
      await tester.pumpAndSettle();
      expect(find.text('내 목소리 결과'), findsOneWidget);
      expect(s.result, same(accepted));
      await tester.tap(find.byKey(const Key('prosody-back')));
      await tester.pumpAndSettle();
      s.failStart = true;
      await tester.tap(find.byKey(const Key('prosody-record-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('목소리 녹음'), findsOneWidget);
      expect(s.result, same(accepted));
      expect(tester.takeException(), isNull);
      await _finish(tester, s);
    },
  );

  testWidgets(
    'selected and whole retries return to recorder without starting the microphone',
    (tester) async {
      final s = _ScreenSession();
      s.result = _accepted(s.reference!.analysis);
      await _mount(tester, s);
      await tester.tap(find.byKey(const Key('prosody-practice-region')));
      await tester.pumpAndSettle();
      expect(s.excerpt, isTrue);
      expect(find.text('목소리 녹음'), findsOneWidget);
      expect(s.starts, 0);
      await tester.tap(find.byKey(const Key('prosody-record-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prosody-record-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('내 목소리 결과'), findsOneWidget);
      await tester.tap(find.byKey(const Key('prosody-repeat-whole')));
      await tester.pumpAndSettle();
      expect(s.excerpt, isFalse);
      expect(find.text('목소리 녹음'), findsOneWidget);
      expect(s.starts, 1);
      expect(s.recording, isFalse);
      expect(tester.takeException(), isNull);
      await _finish(tester, s);
    },
  );

  testWidgets(
    'system back stops recording in place, then idle back returns to preparation',
    (tester) async {
      final s = _ScreenSession();
      await _mount(tester, s);
      await tester.tap(find.byKey(const Key('prosody-prepare-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prosody-record-toggle')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(s.recording, isFalse);
      expect((s.audio as _ScreenAudio).cancellations, 1);
      expect(find.text('목소리 녹음'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('연습 준비'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _finish(tester, s);
    },
  );

  testWidgets(
    'system back cancels guide preparation and keeps the script view',
    (tester) async {
      final s = _ScreenSession();
      await _mount(tester, s);
      await tester.tap(find.byKey(const Key('prosody-script-mode')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('prosody-script-input')),
        '오늘은 발표 연습을 합니다.',
      );
      await tester.ensureVisible(find.byKey(const Key('prosody-apply-script')));
      await tester.tap(find.byKey(const Key('prosody-apply-script')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('prosody-generate-guide')),
      );
      await tester.tap(find.byKey(const Key('prosody-generate-guide')));
      await tester.pump();
      expect(s.phase, PracticePhase.generating);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(s.busy, isFalse);
      expect((s.audio as _ScreenAudio).guideCancellations, 1);
      expect(find.text('연습 준비'), findsOneWidget);
      expect(s.usingScript, isTrue);
      await tester.drag(
        find.byKey(const PageStorageKey('prosody-prepare-scroll')),
        const Offset(0, 1200),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('prosody-script-input')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _finish(tester, s);
    },
  );

  testWidgets(
    'start and finish stay locked throughout delayed cancellation and playback cleanup',
    (tester) async {
      final s = _ScreenSession();
      await _mount(tester, s);
      await tester.tap(find.byKey(const Key('prosody-prepare-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prosody-record-toggle')));
      await tester.pumpAndSettle();
      final audio = s.audio as _ScreenAudio;
      audio.cancellationGate = Completer<void>();
      audio.playbackStopGate = Completer<void>();
      await tester.tap(find.byKey(const Key('prosody-back')));
      await tester.pump();
      final toggle = find.byKey(const Key('prosody-record-toggle'));
      expect(tester.widget<FilledButton>(toggle).onPressed, isNull);
      await tester.tap(toggle);
      await tester.pump();
      expect(s.starts, 1);
      expect(s.stops, 0);
      audio.cancellationGate!.complete();
      await tester.pumpAndSettle();
      expect(s.recording, isFalse);
      expect(tester.widget<FilledButton>(toggle).onPressed, isNull);
      await tester.tap(toggle);
      await tester.pump();
      expect(s.starts, 1);
      audio.playbackStopGate!.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(toggle).onPressed, isNotNull);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(s.starts, 2);
      expect(find.text('목소리 녹음'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _finish(tester, s);
    },
  );

  testWidgets(
    '320px large text keeps start finish and cancel controls reachable above the main tabs',
    (tester) async {
      final s = _ScreenSession();
      await _mount(tester, s, width: 320, height: 568, scale: 2);
      expect(
        find.byKey(const Key('prosody-prepare-next')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('prosody-prepare-next')));
      await tester.pumpAndSettle();
      final control = find.byKey(const Key('prosody-record-toggle'));
      expect(control.hitTestable(), findsOneWidget);
      expect(
        tester.widget<ProsodyChart>(find.byType(ProsodyChart)).height,
        greaterThanOrEqualTo(180),
      );
      await tester.tap(control);
      await tester.pumpAndSettle();
      expect(control.hitTestable(), findsOneWidget);
      expect(
        find.byKey(const Key('prosody-record-cancel')).hitTestable(),
        findsOneWidget,
      );
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('prosody-record-cancel')));
      await tester.pumpAndSettle();
      expect(s.recording, isFalse);
      expect(find.text('목소리 녹음'), findsOneWidget);
      await _finish(tester, s);
    },
  );
}
