import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/app.dart';
import 'package:voicemate/audio/audio_port.dart';
import 'package:voicemate/features/pronunciation/data/learning_store.dart';
import 'package:voicemate/features/pronunciation/presentation/pronunciation_screen.dart';
import 'package:voicemate/features/prosody/presentation/prosody_screen.dart';
import 'package:voicemate/features/prosody/practice_session.dart';
import 'package:voicemate/features/prosody/services/device_audio.dart';

import 'fake_audio_port.dart';

void main() {
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
    await tester.ensureVisible(find.byKey(const Key('enrollment-skip')));
    await tester.tap(find.byKey(const Key('enrollment-skip')));
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
  Completer<void>? cancelGate;
  @override
  Future<void> stopPlayback() async => playbackStops++;
  @override
  Future<void> cancelGuide() async {}
  @override
  Future<void> cancel() async {
    recordingCancels++;
    await cancelGate?.future;
  }
}
