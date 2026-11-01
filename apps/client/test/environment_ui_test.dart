import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/audio/audio_port.dart';
import 'package:voicemate/scenario.dart';
import 'package:voicemate/screens/meter_screen.dart';
import 'package:voicemate/session_controller.dart';
import 'fake_audio_port.dart';

void main() {
  testWidgets('public version disables unavailable speaker enrollment', (
    tester,
  ) async {
    final port = FakeAudioPort();
    final session = SessionController(port)
      ..selectScenario(Scenario.values.first);
    await session.start();
    port.send(const AudioEvent.settings({'speakerAvailable': false}));
    port.send(const AudioEvent.state(CaptureState.running));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MeterScreen(session: session, onBack: () {}),
          ),
        ),
      ),
    );
    expect(find.text('현재 공개 버전에서는 화자 등록을 제공하지 않음'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('begin-speaker-enrollment')),
          )
          .onPressed,
      isNull,
    );
    session.dispose();
  });

  test(
    'mode change keeps registration and clears old speaker result',
    () async {
      final port = FakeAudioPort();
      final session = SessionController(port)
        ..selectScenario(Scenario.values.first);
      await session.start();
      port.send(const AudioEvent.state(CaptureState.running));
      port.send(const AudioEvent.speaker({'state': 'registered'}));
      port.send(
        const AudioEvent.speaker({
          'state': 'similar',
          'startTime': 1.0,
          'endTime': 2.0,
        }),
      );
      await session.stop();
      session.selectScenario(Scenario.values.last);
      await session.start();
      port.send(const AudioEvent.state(CaptureState.running));
      expect(session.speakerRegistered, isTrue);
      expect(session.speaker, {'state': 'confirming'});
      expect(port.speakerDeletes, 0);
      session.dispose();
    },
  );
  test(
    'stopping during registration clears stale registration state',
    () async {
      final port = FakeAudioPort();
      final session = SessionController(port)
        ..selectScenario(Scenario.values.first);
      await session.start();
      port.send(const AudioEvent.settings({'speakerAvailable': true}));
      port.send(const AudioEvent.state(CaptureState.running));
      port.send(
        const AudioEvent.speaker({'state': 'registering', 'samples': 1}),
      );
      port.send(const AudioEvent.state(CaptureState.idle));
      port.send(const AudioEvent.speaker({'state': 'unregistered'}));
      expect(session.speaker['state'], 'unregistered');
      session.dispose();
    },
  );
  testWidgets(
    'speaker registration is voluntary, deletable, and independent of relative input',
    (tester) async {
      final port = FakeAudioPort();
      final session = SessionController(port)
        ..selectScenario(Scenario.values.first);
      await session.start();
      port.send(const AudioEvent.settings({'speakerAvailable': true}));
      port.send(const AudioEvent.state(CaptureState.running));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnimatedBuilder(
                animation: session,
                builder: (_, _) => MeterScreen(session: session, onBack: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.ensureVisible(
        find.byKey(const Key('begin-speaker-enrollment')),
      );
      await tester.tap(find.byKey(const Key('begin-speaker-enrollment')));
      await tester.pump();
      expect(port.speakerEnrollments, 1);
      port.send(const AudioEvent.speaker({'state': 'registered'}));
      port.send(
        const AudioEvent.analysis({
          'state': 'unavailable',
          'reason': 'processing_settings',
          'speech': 'speech',
          'meterState': 'speech',
          'meterDbfs': -40.0,
        }),
      );
      await tester.pump();
      expect(find.byKey(const Key('input-fill')), findsOneWidget);
      expect(find.textContaining('등록 완료'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('speaker-model-notice')));
      await tester.tap(find.byKey(const Key('speaker-model-notice')));
      await tester.pumpAndSettle();
      expect(find.text('화자 모델 및 라이선스'), findsOneWidget);
      expect(find.textContaining('WeSpeaker contributors'), findsOneWidget);
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
      port.send(
        const AudioEvent.speaker({
          'state': 'similar',
          'startTime': 1.0,
          'endTime': 2.0,
          'delayMs': 200.0,
        }),
      );
      await tester.pump();
      expect(find.textContaining('1.00–2.00'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('delete-speaker')));
      await tester.tap(find.byKey(const Key('delete-speaker')));
      await tester.pump();
      expect(port.speakerDeletes, 1);
      expect(find.textContaining('등록되지 않음'), findsOneWidget);
      session.dispose();
    },
  );
  testWidgets(
    'unavailable speaker verifier is explicit and does not block the relative meter',
    (tester) async {
      final port = FakeAudioPort();
      final session = SessionController(port)
        ..selectScenario(Scenario.values.first);
      await session.start();
      port.send(const AudioEvent.state(CaptureState.running));
      port.send(
        const AudioEvent.analysis({
          'state': 'unavailable',
          'reason': 'processing_settings',
          'speech': 'speech',
          'meterState': 'speech',
          'meterDbfs': -40.0,
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MeterScreen(session: session, onBack: () {}),
            ),
          ),
        ),
      );
      expect(find.textContaining('화자 확인 준비되지 않음'), findsOneWidget);
      expect(find.textContaining('상대 입력'), findsWidgets);
      expect(find.byKey(const Key('input-fill')), findsOneWidget);
      session.dispose();
    },
  );
  testWidgets('input gap reports that analysis is restarting', (tester) async {
    final port = FakeAudioPort();
    final session = SessionController(port)
      ..selectScenario(Scenario.values.first);
    await session.start();
    port.send(const AudioEvent.state(CaptureState.running));
    port.send(
      const AudioEvent.analysis({
        'state': 'held',
        'meterState': 'unavailable',
        'reason': 'input_gap',
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MeterScreen(session: session, onBack: () {}),
          ),
        ),
      ),
    );
    expect(find.textContaining('입력 프레임이 끊겨 분석을 다시 준비한다.'), findsOneWidget);
    expect(find.byKey(const Key('input-fill')), findsNothing);
    session.dispose();
  });
  testWidgets(
    'relative speech remains visible when environment processing is unknown',
    (tester) async {
      final port = FakeAudioPort();
      final session = SessionController(port)
        ..selectScenario(Scenario.values.first);
      await session.start();
      port.send(
        const AudioEvent.settings({
          'noiseReductionState': 'active',
          'vadStatus': 'ready',
          'echoCancellation': false,
        }),
      );
      port.send(const AudioEvent.state(CaptureState.running));
      port.send(
        const AudioEvent.analysis({
          'state': 'unavailable',
          'reason': 'processing_settings',
          'speech': 'speech',
          'meterState': 'speech',
          'meterDbfs': -40.0,
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MeterScreen(session: session, onBack: () {}),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('input-fill')), findsOneWidget);
      expect(find.textContaining('환경 잡음 추정과 자동 범위를 보류했다.'), findsOneWidget);
      expect(find.textContaining('전처리 미확인 · 막대는 상대 참고값이다.'), findsOneWidget);
      session.dispose();
    },
  );
  testWidgets(
    'input diagnostics distinguish received frames from analysis availability',
    (tester) async {
      final port = FakeAudioPort();
      final session = SessionController(port)
        ..selectScenario(Scenario.values.first);
      await session.start();
      port.send(
        const AudioEvent.settings({
          'noiseReductionState': 'active',
          'vadStatus': 'ready',
          'contextState': 'running',
          'contextSampleRate': 48000,
        }),
      );
      port.send(const AudioEvent.state(CaptureState.running));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnimatedBuilder(
                animation: session,
                builder: (_, _) => MeterScreen(session: session, onBack: () {}),
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('입력 프레임을 기다리고 있다.'), findsOneWidget);
      port.send(
        const AudioEvent.level(
          rms: .1,
          dbfs: -20,
          normalized: .75,
          sampleCount: 4800,
        ),
      );
      port.send(
        const AudioEvent.analysis({
          'state': 'unavailable',
          'reason': 'processing_settings',
        }),
      );
      await tester.pump();
      expect(find.textContaining('입력 프레임 수신: 1'), findsOneWidget);
      expect(find.textContaining('소음 억제 후 -20.0 dBFS'), findsOneWidget);
      expect(find.textContaining('오디오 엔진 실행 중'), findsOneWidget);
      expect(find.byKey(const Key('input-fill')), findsNothing);
      session.dispose();
    },
  );

  testWidgets('resume timeout and no-frame errors have distinct guidance', (
    tester,
  ) async {
    final port = FakeAudioPort();
    final session = SessionController(port)
      ..selectScenario(Scenario.values.first);
    await session.start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnimatedBuilder(
              animation: session,
              builder: (_, _) => MeterScreen(session: session, onBack: () {}),
            ),
          ),
        ),
      ),
    );
    port.send(
      const AudioEvent.state(
        CaptureState.error,
        reason: 'context_resume_timeout',
      ),
    );
    await tester.pump();
    expect(find.textContaining('오디오 엔진이 제때 시작되지 않았다.'), findsOneWidget);
    await session.start();
    port.send(
      const AudioEvent.state(CaptureState.error, reason: 'frame_timeout'),
    );
    await tester.pump();
    expect(find.textContaining('오디오 프레임을 받지 못했다.'), findsOneWidget);
    await session.start();
    port.send(
      const AudioEvent.state(
        CaptureState.error,
        reason: 'settings_unavailable',
      ),
    );
    await tester.pump();
    expect(find.textContaining('마이크 입력 설정을 읽지 못했다.'), findsOneWidget);
    session.dispose();
  });
  testWidgets(
    'speech bar clears immediately for non-speech, uncertainty and held',
    (tester) async {
      final port = FakeAudioPort();
      final session = SessionController(port)
        ..selectScenario(Scenario.values.first);
      await session.start();
      port.send(const AudioEvent.state(CaptureState.running));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnimatedBuilder(
                animation: session,
                builder: (_, _) => MeterScreen(session: session, onBack: () {}),
              ),
            ),
          ),
        ),
      );
      for (final state in ['nonSpeech', 'uncertain', 'held']) {
        port.send(
          const AudioEvent.analysis({
            'state': 'ready',
            'speech': 'speech',
            'meterState': 'speech',
            'meterDbfs': -40.0,
          }),
        );
        await tester.pump();
        expect(find.byKey(const Key('input-fill')), findsOneWidget);
        port.send(
          AudioEvent.analysis({
            'state': state == 'held' ? 'held' : 'ready',
            'speech': state,
            'meterDbfs': -10.0,
          }),
        );
        await tester.pump();
        expect(find.byKey(const Key('input-fill')), findsNothing);
      }
      port.send(
        const AudioEvent.analysis({
          'state': 'held',
          'speech': 'speech',
          'meterState': 'speech',
          'meterDbfs': -40.0,
        }),
      );
      await tester.pump();
      expect(find.byKey(const Key('input-fill')), findsOneWidget);
      expect(find.textContaining('잡음 정보가 오래됐거나 불확실해 보류했다.'), findsOneWidget);
      port.send(
        const AudioEvent.analysis({
          'state': 'collecting',
          'speech': 'speech',
          'meterState': 'confirming',
        }),
      );
      await tester.pump();
      expect(find.byKey(const Key('input-fill')), findsNothing);
      expect(find.text('발화 판정을 연속 확인하고 있다.'), findsOneWidget);
      session.dispose();
    },
  );
  testWidgets(
    'VAD failure and RNNoise unsupported sample rate are distinguishable',
    (tester) async {
      final port = FakeAudioPort();
      final session = SessionController(port)
        ..selectScenario(Scenario.values.first);
      await session.start();
      port.send(
        const AudioEvent.settings({
          'noiseReductionState': 'active',
          'vadStatus': 'init_failed',
        }),
      );
      port.send(const AudioEvent.state(CaptureState.running));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnimatedBuilder(
                animation: session,
                builder: (_, _) => MeterScreen(session: session, onBack: () {}),
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('발화 판별기를 준비하지 못했다.'), findsOneWidget);
      port.send(
        const AudioEvent.settings({
          'noiseReductionState': 'unavailable',
          'noiseReductionReason': 'unsupported_sample_rate',
          'contextSampleRate': 44100,
        }),
      );
      await tester.pump();
      expect(
        find.textContaining('오디오 처리 주파수 44100 Hz는 소음 억제를 지원하지 않는다.'),
        findsOneWidget,
      );
      session.dispose();
    },
  );
  testWidgets('unknown preprocessing is identified above the meter', (
    tester,
  ) async {
    final port = FakeAudioPort();
    final session = SessionController(port)
      ..selectScenario(Scenario.values.first);
    await session.start();
    port.send(
      const AudioEvent.settings({
        'noiseReductionState': 'active',
        'vadStatus': 'ready',
        'echoCancellation': false,
      }),
    );
    port.send(const AudioEvent.state(CaptureState.running));
    port.send(
      const AudioEvent.analysis({
        'state': 'unavailable',
        'reason': 'processing_settings',
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MeterScreen(session: session, onBack: () {}),
          ),
        ),
      ),
    );
    expect(
      find.textContaining('브라우저 처리 설정을 확인할 수 없어 환경 잡음 추정과 자동 범위를 보류했다.'),
      findsOneWidget,
    );
    expect(find.textContaining('자동 이득 확인 불가'), findsOneWidget);
    expect(find.textContaining('잡음 억제 확인 불가'), findsOneWidget);
    expect(find.textContaining('반향 제거 꺼짐'), findsOneWidget);
    port.send(
      const AudioEvent.analysis({
        'state': 'unavailable',
        'reason': 'vad_runtime_failed',
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MeterScreen(session: session, onBack: () {}),
          ),
        ),
      ),
    );
    expect(find.textContaining('발화 판별 중 오류가 발생했다.'), findsOneWidget);
    expect(find.textContaining('발화 판별기 실행 오류'), findsOneWidget);
    port.send(
      const AudioEvent.settings({
        'noiseReductionState': 'active',
        'vadStatus': 'runtime_failed',
        'autoGainControl': true,
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MeterScreen(session: session, onBack: () {}),
          ),
        ),
      ),
    );
    expect(find.textContaining('발화 판별 중 오류가 발생했다.'), findsOneWidget);
    expect(find.textContaining('발화 판별기 실행 오류'), findsOneWidget);
    session.dispose();
  });
  testWidgets('analysis shows separate reference and clears when held', (
    tester,
  ) async {
    final port = FakeAudioPort();
    final session = SessionController(port)
      ..selectScenario(Scenario.values.first);
    await session.start();
    port.send(const AudioEvent.state(CaptureState.running));
    port.send(
      const AudioEvent.settings({
        'autoGainControl': false,
        'noiseSuppression': false,
        'echoCancellation': false,
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnimatedBuilder(
              animation: session,
              builder: (_, _) => MeterScreen(session: session, onBack: () {}),
            ),
          ),
        ),
      ),
    );
    port.send(
      const AudioEvent.analysis({
        'state': 'ready',
        'voiceDbfs': -44.0,
        'noiseDbfs': -60.0,
        'offset': 1.0,
        'speech': 'speech',
        'meterState': 'speech',
      }),
    );
    await tester.pump();
    expect(find.textContaining('환경 적응 참고범위 54.0–76.0'), findsOneWidget);
    port.send(const AudioEvent.analysis({'state': 'held'}));
    await tester.pump();
    expect(find.textContaining('환경 적응 참고범위 54.0–76.0'), findsNothing);
    session.dispose();
  });
}
