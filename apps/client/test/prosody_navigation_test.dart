import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/app.dart';
import 'package:voicemate/audio/audio_port.dart';
import 'package:voicemate/features/pronunciation/data/learning_store.dart';
import 'package:voicemate/features/pronunciation/presentation/pronunciation_screen.dart';
import 'package:voicemate/features/prosody/presentation/prosody_screen.dart';
import 'package:voicemate/features/prosody/audio/audio_analysis.dart';
import 'package:voicemate/features/prosody/audio/wav.dart';
import 'package:voicemate/features/prosody/practice_session.dart';
import 'package:voicemate/features/prosody/practice_feedback.dart';
import 'package:voicemate/features/prosody/services/device_audio.dart';
import 'package:voicemate/screens/scenario_screen.dart';

import 'fake_audio_port.dart';

void main() {
  testWidgets('help waits for cancellation and keeps prosody on return', (
    tester,
  ) async {
    final audio = _CountingProsodyAudio();
    final practice = PracticeSession(audio: audio);
    _seedAcceptedPractice(practice);
    final reference = practice.reference;
    addTearDown(practice.dispose);
    await tester.pumpWidget(
      VoiceMateApp(
        audioPort: FakeAudioPort(),
        prosodySession: practice,
        startWithProsody: true,
      ),
    );
    await tester.pumpAndSettle();
    await practice.startRecording();
    await tester.pump();
    audio.cancelGate = Completer<void>();
    await tester.tap(find.byKey(const Key('open-training-guide')));
    await tester.pump();
    expect(find.text('사용 안내'), findsNothing);
    expect(audio.capturing, isTrue);
    audio.cancelGate!.complete();
    await tester.pumpAndSettle();
    expect(audio.capturing, isFalse);
    expect(find.byType(ProsodyScreen, skipOffstage: false), findsOneWidget);
    expect(find.text('사용 안내'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ProsodyScreen), findsOneWidget);
    expect(practice.reference, same(reference));
    expect(practice.recording, isFalse);
    expect(audio.recordingStarts, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'leaving optional practice preparation returns to volume without starting audio',
    (tester) async {
      final port = FakeAudioPort();
      final audio = _CountingProsodyAudio();
      final practice = PracticeSession(audio: audio);
      addTearDown(practice.dispose);
      await tester.pumpWidget(
        VoiceMateApp(audioPort: port, prosodySession: practice),
      );
      await tester.tap(find.byKey(const Key('open-prosody')));
      await tester.pumpAndSettle();
      expect(find.text('연습 준비'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ScenarioScreen), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      expect(audio.recordingStarts, 0);
      expect(audio.guideGenerations, 0);
      expect(port.starts, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'optional prosody releases an explicit recording before volume returns without auto starting audio',
    (tester) async {
      final port = FakeAudioPort();
      final audio = _CountingProsodyAudio();
      final practice = PracticeSession(audio: audio);
      _seedAcceptedPractice(practice);
      final acceptedGuide = practice.reference,
          acceptedResult = practice.result;
      addTearDown(practice.dispose);
      await tester.pumpWidget(
        VoiceMateApp(audioPort: port, prosodySession: practice),
      );
      expect(find.byType(ScenarioScreen), findsOneWidget);
      expect(find.byType(ProsodyScreen), findsNothing);
      expect(port.starts, 0);
      expect(audio.recordingStarts, 0);

      await tester.tap(find.byKey(const Key('open-prosody')));
      await tester.pumpAndSettle();
      expect(find.byType(ProsodyScreen), findsOneWidget);
      expect(audio.recordingStarts, 0);
      expect(audio.guideGenerations, 0);
      expect(audio.playbackStarts, 0);
      expect(practice.recording, isFalse);

      await practice.startRecording();
      await tester.pump();
      expect(audio.recordingStarts, 1);
      expect(audio.capturing, isTrue);
      expect(practice.recording, isTrue);
      audio.cancelGate = Completer<void>();
      await tester.tap(find.widgetWithText(NavigationDestination, '음량 측정'));
      await tester.pump();
      expect(audio.recordingCancels, 1);
      expect(audio.capturing, isTrue);
      expect(find.byType(ProsodyScreen), findsOneWidget);
      expect(find.byType(ScenarioScreen), findsNothing);
      expect(port.starts, 0);

      audio.cancelGate!.complete();
      await tester.pumpAndSettle();
      expect(audio.capturing, isFalse);
      expect(practice.recording, isFalse);
      expect(find.byType(ProsodyScreen), findsNothing);
      expect(find.byType(ScenarioScreen), findsOneWidget);
      expect(port.starts, 0);

      await tester.tap(find.byKey(const Key('open-prosody')));
      await tester.pumpAndSettle();
      expect(practice.reference, same(acceptedGuide));
      expect(practice.result, same(acceptedResult));
      expect(practice.recording, isFalse);
      expect(audio.capturing, isFalse);
      expect(audio.recordingStarts, 1);
      expect(audio.guideGenerations, 0);
      expect(audio.playbackStarts, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('volume capture stops before the prosody tab opens', (
    tester,
  ) async {
    final port = FakeAudioPort();
    final audio = _CountingProsodyAudio();
    final practice = PracticeSession(audio: audio);
    final learning = LearningController(MemoryLearningStore());
    addTearDown(practice.dispose);
    addTearDown(learning.dispose);
    await tester.pumpWidget(
      VoiceMateApp(
        audioPort: port,
        prosodySession: practice,
        pronunciationLearning: learning,
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('scenario-quiet')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('start')));
    await tester.tap(find.byKey(const Key('start')));
    await tester.pumpAndSettle();
    port.send(const AudioEvent.state(CaptureState.running));
    await tester.pump();

    port.stopGate = Completer<void>();
    await tester.tap(find.byKey(const Key('open-prosody')));
    await tester.pump();
    expect(port.stops, 1);
    expect(find.byType(ProsodyScreen), findsNothing);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(
      find.ancestor(
        of: find.byKey(const Key('toggle-capture')),
        matching: find.byWidgetPredicate(
          (widget) => widget is AbsorbPointer && widget.absorbing,
        ),
      ),
      findsOneWidget,
    );

    port.stopGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(ProsodyScreen), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );

    practice.setVolume(true);
    audio.cancelGate = Completer<void>();
    await tester.tap(find.byKey(const Key('open-pronunciation')));
    await tester.pump();
    expect(audio.playbackStops, 1);
    expect(audio.recordingCancels, 1);
    expect(find.byType(ProsodyScreen), findsOneWidget);
    expect(find.byType(PronunciationScreen), findsNothing);
    audio.cancelGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(ProsodyScreen), findsNothing);
    expect(find.byType(PronunciationScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-prosody')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ProsodyScreen>(find.byType(ProsodyScreen)).session,
      same(practice),
    );
    expect(practice.volume, isTrue);
    await tester.tap(find.widgetWithText(NavigationDestination, '음량 측정'));
    await tester.pumpAndSettle();
    expect(port.starts, 1);
    expect(find.byKey(const Key('toggle-capture')), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'existing pronunciation start and third tab both remain available',
    (tester) async {
      final audio = _CountingProsodyAudio();
      final practice = PracticeSession(audio: audio);
      final learning = LearningController(MemoryLearningStore());
      addTearDown(practice.dispose);
      addTearDown(learning.dispose);
      await tester.pumpWidget(
        VoiceMateApp(
          audioPort: FakeAudioPort(),
          startWithPronunciation: true,
          prosodySession: practice,
          pronunciationLearning: learning,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PronunciationScreen), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      expect(find.byType(NavigationDestination), findsNWidgets(3));

      await tester.tap(find.byKey(const Key('open-prosody')));
      await tester.pumpAndSettle();
      expect(find.byType(PronunciationScreen), findsNothing);
      expect(find.byType(ProsodyScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}

class _CountingProsodyAudio extends DeviceAudioService {
  int playbackStops = 0, recordingCancels = 0;
  int recordingStarts = 0, guideGenerations = 0, playbackStarts = 0;
  bool capturing = false;
  Completer<void>? cancelGate;
  @override
  Future<void> start({
    required void Function(List<double> samples) onSamples,
    void Function()? onLimitReached,
    void Function(String message)? onError,
  }) async {
    recordingStarts++;
    capturing = true;
  }

  @override
  Future<GeneratedGuide> generateGuide(String text) async {
    guideGenerations++;
    throw const DeviceAudioException('Navigation must not generate a guide.');
  }

  @override
  Future<void> play(
    String path, {
    Duration? start,
    Duration? end,
    bool waitForCompletion = false,
  }) async {
    playbackStarts++;
  }

  @override
  Future<void> stopPlayback() async => playbackStops++;
  @override
  Future<void> cancelGuide() async {}
  @override
  Future<void> cancel() async {
    recordingCancels++;
    await cancelGate?.future;
    capturing = false;
  }
}

void _seedAcceptedPractice(PracticeSession practice) {
  final samples = List<double>.generate(
    16000,
    (i) => .2 * math.sin(2 * math.pi * 220 * i / 16000),
  );
  final analysis = trimAnalysis(analyzeSamples(samples, 16000));
  final comparison = compareAnalyses(analysis, analysis);
  practice.reference = ReferenceClip(
    '안녕하세요.',
    'synthetic-guide.wav',
    analysis,
    'Navigation test fixture',
  );
  practice.result = PracticeResult(
    RecordedAudio(
      samples: samples,
      sampleRate: 16000,
      path: 'synthetic-recording.wav',
      bytes: encodeWav(samples, 16000),
    ),
    analysis,
    comparison,
    buildPracticeSummary(analysis, analysis, comparison),
    alignedTrace(analysis, analysis, comparison.path),
  );
}
