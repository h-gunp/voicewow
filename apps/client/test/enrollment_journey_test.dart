import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/app.dart';
import 'package:voicemate/audio/audio_port.dart';
import 'package:voicemate/session_controller.dart';
import 'fake_audio_port.dart';

void main() {
  testWidgets('enrollment then mode selection, with double start guarded', (
    tester,
  ) async {
    final port = FakeAudioPort();
    await tester.pumpWidget(VoiceMateApp(audioPort: port));
    expect(find.text('내 목소리 등록하기'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('enrollment-start')));
    await tester.tap(find.byKey(const Key('enrollment-start')));
    await tester.pump();
    expect(port.starts, 1);
    port.send(
      const AudioEvent.settings({
        'speakerAvailable': true,
        'noiseReductionState': 'active',
        'vadStatus': 'ready',
      }),
    );
    port.send(const AudioEvent.state(CaptureState.running));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('enrollment-record')));
    await tester.tap(find.byKey(const Key('enrollment-record')));
    await tester.pump();
    final record = tester.widget<FilledButton>(
      find.byKey(const Key('enrollment-record')),
    );
    expect(record.onPressed, isNull);
    port.send(const AudioEvent.speaker({'state': 'registering', 'samples': 1}));
    await tester.pump();
    expect(find.textContaining('1/3'), findsOneWidget);
    expect(port.speakerEnrollments, 1);
    port.send(const AudioEvent.speaker({'state': 'registered'}));
    await tester.pump();
    port.send(const AudioEvent.speaker({'state': 'quality'}));
    await tester.pump();
    expect(find.text('등록 완료 · 3/3'), findsOneWidget);
    port.send(
      const AudioEvent.speaker({
        'state': 'similar',
        'startTime': 1.0,
        'endTime': 2.0,
        'delayMs': 100.0,
      }),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.ensureVisible(find.byKey(const Key('enrollment-continue')));
    await tester.tap(find.byKey(const Key('enrollment-continue')));
    await tester.pump();
    expect(find.text('모드 선택'), findsOneWidget);
  });
  testWidgets('skip leads to mode selection', (tester) async {
    final port = FakeAudioPort();
    await tester.pumpWidget(VoiceMateApp(audioPort: port));
    await tester.ensureVisible(find.byKey(const Key('enrollment-skip')));
    await tester.tap(find.byKey(const Key('enrollment-skip')));
    await tester.pump();
    expect(find.text('모드 선택'), findsOneWidget);
    expect(port.starts, 0);
  });
  testWidgets('not ready, model failure, retry and cancel are distinct', (
    tester,
  ) async {
    final port = FakeAudioPort();
    await tester.pumpWidget(VoiceMateApp(audioPort: port));
    await tester.ensureVisible(find.byKey(const Key('enrollment-start')));
    await tester.tap(find.byKey(const Key('enrollment-start')));
    await tester.pump();
    port.send(
      const AudioEvent.settings({
        'speakerAvailable': true,
        'noiseReductionState': 'active',
        'vadStatus': 'load_failed',
      }),
    );
    port.send(const AudioEvent.state(CaptureState.running));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('enrollment-record')))
          .onPressed,
      isNull,
    );
    port.send(
      const AudioEvent.settings({
        'speakerAvailable': true,
        'noiseReductionState': 'active',
        'vadStatus': 'ready',
      }),
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('enrollment-record')));
    await tester.tap(find.byKey(const Key('enrollment-record')));
    await tester.pump();
    port.send(const AudioEvent.speaker({'state': 'loading', 'samples': 0}));
    await tester.pump();
    expect(find.text('음성 모델을 준비하고 있다.'), findsOneWidget);
    port.send(const AudioEvent.speaker({'state': 'unavailable'}));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('enrollment-record')));
    await tester.tap(find.byKey(const Key('enrollment-record')));
    await tester.pump();
    expect(port.speakerEnrollments, 2);
    await tester.ensureVisible(find.byKey(const Key('enrollment-cancel')));
    await tester.tap(find.byKey(const Key('enrollment-cancel')));
    await tester.pump();
    expect(port.speakerDeletes, 1);
    expect(port.stops, 1);
  });
  test(
    'enrollment restores required noise suppression after it was disabled',
    () async {
      final port = FakeAudioPort();
      final session = SessionController(port);
      await session.setNoiseReductionEnabled(false);
      await session.start(enrollment: true);
      expect(port.noiseReductionSelections, [true]);
      session.dispose();
    },
  );
  test('consecutive enrollment calls start only once', () async {
    final port = FakeAudioPort();
    final session = SessionController(port);
    await session.start(enrollment: true);
    port.send(
      const AudioEvent.settings({
        'speakerAvailable': true,
        'noiseReductionState': 'active',
        'vadStatus': 'ready',
      }),
    );
    port.send(const AudioEvent.state(CaptureState.running));
    await Future.wait([
      session.beginSpeakerEnrollment(),
      session.beginSpeakerEnrollment(),
    ]);
    expect(port.speakerEnrollments, 1);
    session.dispose();
  });

  test('device removal invalidates completion', () async {
    final port = FakeAudioPort();
    final session = SessionController(port);
    await session.start(enrollment: true);
    port.send(
      const AudioEvent.settings({
        'speakerAvailable': true,
        'noiseReductionState': 'active',
        'vadStatus': 'ready',
      }),
    );
    port.send(const AudioEvent.state(CaptureState.running));
    await session.beginSpeakerEnrollment();
    port.send(const AudioEvent.speaker({'state': 'registered'}));
    expect(session.enrollmentComplete, isTrue);
    port.send(const AudioEvent.speaker({'state': 'unregistered'}));
    port.send(
      const AudioEvent.state(CaptureState.idle, reason: 'device_changed'),
    );
    expect(session.enrollmentComplete, isFalse);
    expect(session.speakerRegistered, isFalse);
    session.dispose();
  });
  test('ordinary stop preserves completed profile', () async {
    final port = FakeAudioPort();
    final session = SessionController(port);
    await session.start(enrollment: true);
    port.send(
      const AudioEvent.settings({
        'speakerAvailable': true,
        'noiseReductionState': 'active',
        'vadStatus': 'ready',
      }),
    );
    port.send(const AudioEvent.state(CaptureState.running));
    await session.beginSpeakerEnrollment();
    port.send(const AudioEvent.speaker({'state': 'registered'}));
    await session.stop();
    expect(session.enrollmentComplete, isTrue);
    expect(session.speakerRegistered, isTrue);
    session.dispose();
  });
  testWidgets('delayed stop prevents a new start during transition', (
    tester,
  ) async {
    final port = FakeAudioPort();
    await tester.pumpWidget(VoiceMateApp(audioPort: port));
    await tester.ensureVisible(find.byKey(const Key('enrollment-start')));
    await tester.tap(find.byKey(const Key('enrollment-start')));
    await tester.pump();
    port.send(const AudioEvent.state(CaptureState.running));
    await tester.pump();
    port.stopGate = Completer<void>();
    await tester.ensureVisible(find.byKey(const Key('enrollment-skip')));
    await tester.tap(find.byKey(const Key('enrollment-skip')));
    await tester.pump();
    expect(find.byKey(const Key('enrollment-start')), findsNothing);
    expect(port.starts, 1);
    port.stopGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('모드 선택'), findsOneWidget);
  });
  testWidgets('model notice is accessible before microphone', (tester) async {
    final port = FakeAudioPort();
    await tester.pumpWidget(VoiceMateApp(audioPort: port));
    await tester.ensureVisible(find.byKey(const Key('enrollment-info')));
    await tester.tap(find.byKey(const Key('enrollment-info')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('speaker-model-notice')));
    await tester.pumpAndSettle();
    expect(find.textContaining('WeSpeaker contributors'), findsOneWidget);
    expect(port.starts, 0);
  });

  testWidgets(
    'guidance follows collection and never mislabels quality or loading',
    (tester) async {
      final port = FakeAudioPort();
      await tester.pumpWidget(VoiceMateApp(audioPort: port));
      expect(find.text('내 목소리 등록하기'), findsOneWidget);
      expect(find.textContaining('가능하면 조용한 곳에서'), findsOneWidget);
      expect(find.text('이 문장을 편하게 읽어 주세요'), findsOneWidget);
      expect(
        find.textContaining('안녕하세요. 지금 제 목소리를 등록하고 있습니다.'),
        findsOneWidget,
      );
      expect(find.text('등록 중 안내'), findsOneWidget);
      expect(find.textContaining('음성은 기기 안에서 처리'), findsOneWidget);
      expect(find.textContaining('계속 말해 주세요'), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('enrollment-start')));
      await tester.tap(find.byKey(const Key('enrollment-start')));
      await tester.pump();
      port.send(
        const AudioEvent.settings({
          'speakerAvailable': true,
          'noiseReductionState': 'active',
          'vadStatus': 'ready',
        }),
      );
      port.send(const AudioEvent.state(CaptureState.running));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('enrollment-record')));
      await tester.tap(find.byKey(const Key('enrollment-record')));
      await tester.pump();
      expect(
        find.textContaining('진행 표시가 3/3이 될 때까지 계속 말해 주세요.'),
        findsOneWidget,
      );
      port.send(const AudioEvent.speaker({'state': 'loading', 'samples': 0}));
      await tester.pump();
      expect(find.text('음성 모델을 준비하고 있다.'), findsOneWidget);
      expect(find.textContaining('계속 말해 주세요'), findsNothing);
      port.send(const AudioEvent.speaker({'state': 'quality', 'samples': 0}));
      await tester.pump();
      expect(find.textContaining('계속 말'), findsNothing);
      expect(find.textContaining('0/3'), findsOneWidget);
      port.send(
        const AudioEvent.speaker({'state': 'registering', 'samples': 1}),
      );
      await tester.pump();
      expect(
        find.textContaining('진행 표시가 3/3이 될 때까지 계속 말해 주세요.'),
        findsOneWidget,
      );
      port.send(const AudioEvent.speaker({'state': 'quality', 'samples': 1}));
      await tester.pump();
      expect(find.textContaining('계속 말해 주세요'), findsNothing);
      port.send(const AudioEvent.speaker({'state': 'registered'}));
      await tester.pump();
      expect(find.text('등록 완료 · 3/3'), findsOneWidget);
      expect(find.textContaining('계속 말해 주세요'), findsNothing);
    },
  );

  testWidgets('guidance remains scrollable at 320x568 and double text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = FakeAudioPort();
    await tester.pumpWidget(
      VoiceMateApp(audioPort: port, textScaler: const TextScaler.linear(2)),
    );
    await tester.ensureVisible(find.byKey(const Key('enrollment-start')));
    await tester.tap(find.byKey(const Key('enrollment-start')));
    await tester.pump();
    port.send(
      const AudioEvent.settings({
        'speakerAvailable': true,
        'noiseReductionState': 'active',
        'vadStatus': 'ready',
      }),
    );
    port.send(const AudioEvent.state(CaptureState.running));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('enrollment-record')));
    await tester.tap(find.byKey(const Key('enrollment-record')));
    await tester.pump();
    await tester.ensureVisible(find.textContaining('진행 표시가 3/3이 될 때까지'));
    expect(tester.takeException(), isNull);
    port.send(const AudioEvent.speaker({'state': 'quality', 'samples': 0}));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('enrollment-status')));
    expect(find.textContaining('계속 말해 주세요'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('enrollment-skip')));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('enrollment-skip')), findsOneWidget);
    await tester.tap(find.byKey(const Key('enrollment-skip')));
    await tester.pump();
    expect(find.text('모드 선택'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
