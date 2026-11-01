import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/audio/audio_port.dart';
import 'package:voicemate/scenario.dart';
import 'package:voicemate/session_controller.dart';
import 'fake_audio_port.dart';

void main() {
  late FakeAudioPort port;
  late SessionController session;
  setUp(() {
    port = FakeAudioPort();
    session = SessionController(port);
  });
  tearDown(() {
    session.dispose();
  });
  test('selection is required before capture', () async {
    await session.start();
    expect(port.starts, 0);
  });
  test(
    'fresh speech remains visible while noise is collecting or held',
    () async {
      session.selectScenario(Scenario.values.first);
      await session.start();
      port.send(const AudioEvent.state(CaptureState.running));
      for (final noiseState in ['collecting', 'held', 'unsupported']) {
        port.send(
          AudioEvent.analysis({
            'state': noiseState,
            'speech': 'speech',
            'meterState': 'speech',
            'meterDbfs': -40.0,
          }),
        );
        expect(session.displayLevel, 74.0);
      }
      port.send(
        const AudioEvent.analysis({
          'state': 'held',
          'reason': 'analysis_stale',
          'meterState': 'unavailable',
        }),
      );
      expect(session.displayLevel, isNull);
    },
  );
  test(
    'meter uses only a ready speech frame and clears on every unsafe state',
    () async {
      session.selectScenario(Scenario.values.first);
      await session.start();
      port.send(const AudioEvent.state(CaptureState.running));
      port.send(
        const AudioEvent.level(
          rms: .9,
          dbfs: -1,
          normalized: .9,
          sampleCount: 4800,
        ),
      );
      expect(session.displayLevel, isNull);
      port.send(
        const AudioEvent.analysis({
          'state': 'ready',
          'speech': 'speech',
          'meterState': 'speech',
          'meterDbfs': -40.0,
        }),
      );
      expect(session.displayLevel, 74.0);
      for (final event in [
        {'state': 'ready', 'speech': 'nonSpeech', 'meterDbfs': -20.0},
        {'state': 'ready', 'speech': 'uncertain', 'meterDbfs': -20.0},
        {'state': 'held', 'speech': 'speech', 'meterDbfs': -20.0},
        {'state': 'collecting', 'speech': 'speech', 'meterDbfs': -20.0},
        {'state': 'unavailable'},
      ]) {
        port.send(AudioEvent.analysis(event));
        expect(session.displayLevel, isNull);
      }
      await session.stop();
      expect(session.displayLevel, isNull);
      session.selectScenario(Scenario.values[1]);
      await session.start();
      port.send(const AudioEvent.state(CaptureState.running));
      port.send(
        const AudioEvent.level(
          rms: .9,
          dbfs: -1,
          normalized: .9,
          sampleCount: 4800,
        ),
      );
      expect(session.displayLevel, isNull);
    },
  );
  test('analysis is cleared on stop and late analysis is ignored', () async {
    session.selectScenario(Scenario.values.first);
    await session.start();
    port.send(const AudioEvent.state(CaptureState.running));
    port.send(const AudioEvent.analysis({'state': 'ready', 'offset': 1.0}));
    expect(session.analysis['state'], 'ready');
    await session.stop();
    port.send(const AudioEvent.analysis({'state': 'ready', 'offset': 2.0}));
    expect(session.analysis, isEmpty);
  });
  test(
    'duplicate start is ignored and late events after stop are discarded',
    () async {
      session.selectScenario(Scenario.values.first);
      port.gate = Completer<void>();
      final pending = session.start();
      session.start();
      expect(port.starts, 1);
      await session.stop();
      port.send(const AudioEvent.state(CaptureState.running));
      port.send(
        const AudioEvent.level(
          rms: .5,
          dbfs: -6,
          normalized: .925,
          sampleCount: 4800,
        ),
      );
      port.gate!.complete();
      await pending;
      expect(session.state, CaptureState.idle);
      expect(session.level, isNull);
    },
  );
  test('running event receives genuine levels and idle clears them', () async {
    session.selectScenario(Scenario.values.first);
    await session.start();
    port.send(const AudioEvent.state(CaptureState.running));
    port.send(
      const AudioEvent.level(
        rms: .5,
        dbfs: -6,
        normalized: .925,
        sampleCount: 4800,
      ),
    );
    expect(session.level?.dbfs, -6);
    port.send(const AudioEvent.state(CaptureState.idle, reason: 'tab_hidden'));
    expect(session.level, isNull);
    expect(session.reason, 'tab_hidden');
  });
  test('errors clear level and preserve actionable reason', () async {
    session.selectScenario(Scenario.values.first);
    await session.start();
    port.send(
      const AudioEvent.state(CaptureState.error, reason: 'permission_denied'),
    );
    expect(session.state, CaptureState.error);
    expect(session.reason, 'permission_denied');
    expect(session.level, isNull);
  });
  test('late stop completion cannot overwrite a restarted input', () async {
    session.selectScenario(Scenario.values.first);
    await session.start();
    port.send(const AudioEvent.state(CaptureState.running));
    port.stopGate = Completer<void>();
    final changing = session.stop();
    await session.start();
    port.send(const AudioEvent.state(CaptureState.running));
    port.stopGate!.complete();
    await changing;
    expect(session.state, CaptureState.running);
  });
}
