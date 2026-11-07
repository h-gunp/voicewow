import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/audio/audio_port.dart';
import 'package:voicemate/scenario.dart';
import 'package:voicemate/screens/meter_screen.dart';
import 'package:voicemate/session_controller.dart';
import 'fake_audio_port.dart';

const readySettings = <String, Object?>{
  'noiseReductionState': 'active',
  'vadStatus': 'ready',
  'autoGainControl': false,
  'noiseSuppression': false,
  'echoCancellation': false,
};
const calibrated = <String, Object?>{
  'state': 'ready',
  'calibrationValid': true,
  'progress': 1.0,
  'noiseDbfs': -40.0,
  'offset': 2.0,
  'reason': null,
  'provenance': 'verified',
  'speech': 'speech',
  'meterState': 'speech',
  'meterDbfs': -40.0,
};

void main() {
  Future<SessionController> running(FakeAudioPort port) async {
    final session = SessionController(port)
      ..selectScenario(Scenario.values.first);
    addTearDown(session.dispose);
    await session.start();
    port.send(const AudioEvent.settings(readySettings));
    port.send(const AudioEvent.state(CaptureState.running));
    return session;
  }

  test(
    'sampling requires live RNNoise and VAD with supported input settings',
    () async {
      final port = FakeAudioPort();
      final session = await running(port);
      expect(session.canSampleEnvironment, isTrue);
      for (final settings in [
        {...readySettings, 'noiseReductionState': 'disabled'},
        {...readySettings, 'noiseReductionState': 'unavailable'},
        {...readySettings, 'vadStatus': 'init_failed'},
        {...readySettings, 'autoGainControl': true},
        {...readySettings, 'noiseSuppression': null},
        {...readySettings, 'echoCancellation': 'all'},
      ]) {
        port.send(AudioEvent.settings(settings));
        expect(session.canSampleEnvironment, isFalse);
        await session.sampleEnvironment();
        expect(session.environmentCollecting, isFalse);
      }
      expect(port.samples, 0);
      port.send(
        const AudioEvent.settings({
          'noiseReductionState': 'active',
          'vadStatus': 'ready',
        }),
      );
      expect(session.canSampleEnvironment, isTrue);
      await session.sampleEnvironment();
      expect(session.environmentCollecting, isTrue);
      expect(port.samples, 1);
      await session.sampleEnvironment();
      expect(port.samples, 1);
      await session.stop();
      expect(session.canSampleEnvironment, isFalse);
      await session.sampleEnvironment();
      expect(port.samples, 1);
    },
  );

  test(
    'sampling progress and success keep the same microphone capture',
    () async {
      final port = FakeAudioPort();
      final session = await running(port);
      port.send(const AudioEvent.analysis(calibrated));
      await session.sampleEnvironment();
      expect(session.environmentCollecting, isTrue);
      expect(session.displayLevel, isNull);
      expect(session.effectiveRange.lower, 55);
      port.send(
        AudioEvent.analysis({
          ...calibrated,
          'state': 'collecting',
          'progress': .4,
        }),
      );
      expect(session.environmentProgress, .4);
      port.send(AudioEvent.analysis({...calibrated, 'offset': 1.0}));
      expect(session.environmentCollecting, isFalse);
      expect(session.effectiveRange.lower, 54);
      expect(session.displayLevel, 74);
      expect(port.starts, 1);
      expect(port.stops, 0);
    },
  );

  test(
    'sample rejection retains the last valid reference and permits retry',
    () async {
      final port = FakeAudioPort();
      final session = await running(port);
      port.send(const AudioEvent.analysis(calibrated));
      port.sampleGate = Completer<void>();
      final sampling = session.sampleEnvironment();
      port.sampleGate!.completeError(StateError('sample failed'));
      await sampling;
      expect(session.analysis['state'], 'failed');
      expect(session.analysis['reason'], 'sample_failed');
      expect(session.effectiveRange.lower, 55);
      expect(session.canSampleEnvironment, isTrue);
      expect(session.displayLevel, isNull);
      port.sampleGate = null;
      await session.sampleEnvironment();
      port.send(
        AudioEvent.analysis({
          ...calibrated,
          'state': 'failed',
          'reason': 'clipping',
        }),
      );
      expect(session.effectiveRange.lower, 55);
      expect(session.analysis['reason'], 'clipping');
    },
  );

  test(
    'cancel retains only an existing result and never restarts input',
    () async {
      final port = FakeAudioPort();
      final session = await running(port);
      await session.sampleEnvironment();
      await session.cancelEnvironment();
      expect(session.analysis['state'], 'idle');
      expect(session.effectiveRange.adjusted, isFalse);
      port.send(const AudioEvent.analysis(calibrated));
      await session.sampleEnvironment();
      await session.cancelEnvironment();
      expect(session.analysis['state'], 'ready');
      expect(session.effectiveRange.lower, 55);
      expect(session.canCancelEnvironment, isFalse);
      expect(port.cancellations, 2);
      expect(port.starts, 1);
      expect(port.stops, 0);
    },
  );

  test(
    'cancel rejection remains collecting and permits another cancel',
    () async {
      final port = FakeAudioPort();
      final session = await running(port);
      port.send(const AudioEvent.analysis(calibrated));
      await session.sampleEnvironment();
      port.cancelGate = Completer<void>();
      final cancelling = session.cancelEnvironment();
      expect(session.canCancelEnvironment, isFalse);
      port.cancelGate!.completeError(StateError('cancel failed'));
      await cancelling;
      expect(session.environmentCollecting, isTrue);
      expect(session.analysis['reason'], 'cancel_failed');
      expect(session.canCancelEnvironment, isTrue);
      expect(session.effectiveRange.lower, 55);
    },
  );

  test(
    'pending cancellation blocks resampling after a completion event',
    () async {
      final port = FakeAudioPort();
      final session = await running(port);
      await session.sampleEnvironment();
      port.cancelGate = Completer<void>();
      final cancelling = session.cancelEnvironment();
      port.send(const AudioEvent.analysis(calibrated));
      expect(session.canSampleEnvironment, isFalse);
      await session.sampleEnvironment();
      expect(port.samples, 1);
      port.cancelGate!.complete();
      await cancelling;
      expect(session.canSampleEnvironment, isTrue);
    },
  );

  for (final boundary in ['stop', 'settings', 'restart']) {
    test(
      'late sample failure cannot restore a result after $boundary',
      () async {
        final port = FakeAudioPort();
        final session = await running(port);
        port.send(const AudioEvent.analysis(calibrated));
        port.sampleGate = Completer<void>();
        final sampling = session.sampleEnvironment();
        if (boundary == 'settings') {
          port.send(
            const AudioEvent.settings({
              ...readySettings,
              'deviceId': 'new-input',
            }),
          );
        } else {
          await session.stop();
          port.send(const AudioEvent.analysis(calibrated));
          if (boundary == 'restart') {
            await session.start();
            port.send(const AudioEvent.settings(readySettings));
            port.send(const AudioEvent.state(CaptureState.running));
          }
        }
        port.sampleGate!.completeError(StateError('late failure'));
        await sampling;
        expect(session.analysis, isEmpty);
        expect(session.effectiveRange.adjusted, isFalse);
      },
    );
  }

  test('late cancel completion cannot clear a new session sample', () async {
    final port = FakeAudioPort();
    final session = await running(port);
    await session.sampleEnvironment();
    port.cancelGate = Completer<void>();
    final cancelling = session.cancelEnvironment();
    await session.stop();
    await session.start();
    port.send(const AudioEvent.settings(readySettings));
    port.send(const AudioEvent.state(CaptureState.running));
    await session.sampleEnvironment();
    port.cancelGate!.complete();
    await cancelling;
    expect(session.environmentCollecting, isTrue);
    expect(session.canCancelEnvironment, isTrue);
    expect(session.effectiveRange.adjusted, isFalse);
  });

  test(
    'only a valid manual result shifts the reference in every sample state',
    () {
      final session = SessionController(FakeAudioPort())
        ..selectScenario(Scenario.values.first)
        ..state = CaptureState.running
        ..settings = readySettings;
      addTearDown(session.dispose);
      session.analysis = {...calibrated, 'calibrationValid': false};
      expect(session.effectiveRange.lower, 53);
      for (final state in ['ready', 'collecting', 'failed', 'idle']) {
        session.analysis = {...calibrated, 'state': state};
        expect(session.effectiveRange.lower, 55, reason: state);
        expect(session.effectiveRange.upper, 77, reason: state);
      }
    },
  );

  test('collecting empties the meter even if a prior speech value remains', () {
    final session = SessionController(FakeAudioPort())
      ..selectScenario(Scenario.values.first)
      ..state = CaptureState.running
      ..analysis = {...calibrated, 'state': 'collecting'};
    addTearDown(session.dispose);
    expect(session.displayLevel, isNull);
  });

  testWidgets('manual sample action exists before any sample', (tester) async {
    final session = SessionController(FakeAudioPort())
      ..selectScenario(Scenario.values.first)
      ..state = CaptureState.running
      ..settings = readySettings;
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MeterScreen(session: session, onBack: () {}),
          ),
        ),
      ),
    );
    expect(find.text('주변 환경음 듣기'), findsOneWidget);
    expect(find.textContaining('기본 참고범위 53.0–75.0'), findsOneWidget);
  });

  testWidgets(
    'mobile large text supports sample progress cancel and resample',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = FakeAudioPort();
      final session = await running(port);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: session,
                builder: (_, _) =>
                    MeterScreen(session: session, onBack: session.stop),
              ),
            ),
          ),
        ),
      );
      final sample = find.byKey(const Key('sample-environment'));
      await tester.ensureVisible(sample);
      await tester.tap(sample);
      await tester.pump();
      expect(port.samples, 1);
      expect(session.environmentCollecting, isTrue);
      expect(find.byKey(const Key('input-fill')), findsNothing);
      port.send(
        AudioEvent.analysis({
          ...calibrated,
          'state': 'collecting',
          'calibrationValid': false,
          'progress': .4,
          'meterState': 'calibrating',
          'meterDbfs': null,
        }),
      );
      await tester.pump();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const Key('environment-progress')),
            )
            .value,
        .4,
      );
      expect(find.textContaining('주변 대화도 포함한다.'), findsOneWidget);
      final cancel = find.byKey(const Key('cancel-environment'));
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      await tester.pump();
      expect(session.environmentCollecting, isFalse);
      expect(find.byKey(const Key('environment-progress')), findsNothing);
      port.send(const AudioEvent.analysis(calibrated));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('다시 측정'), findsOneWidget);
      await tester.ensureVisible(sample);
      await tester.tap(sample);
      await tester.pump();
      port.send(
        AudioEvent.analysis({
          ...calibrated,
          'state': 'failed',
          'reason': 'clipping',
        }),
      );
      await tester.pump();
      expect(find.textContaining('이전에 측정한 환경 기준을 유지한다.'), findsOneWidget);
      expect(find.textContaining('고정 참고범위 55.0–77.0'), findsOneWidget);
      expect(find.textContaining('발화 수준 추정'), findsNothing);
      expect(find.textContaining('주변 잡음 추정'), findsNothing);
      expect(port.starts, 1);
      expect(port.stops, 0);
      await tester.ensureVisible(find.text('상황 변경'));
      await tester.tap(find.text('상황 변경'));
      await tester.pump();
      expect(session.analysis, isEmpty);
      expect(session.state, CaptureState.idle);
      port.send(const AudioEvent.analysis(calibrated));
      expect(session.effectiveRange.adjusted, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
