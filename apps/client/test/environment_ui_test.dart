import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/audio/audio_port.dart';
import 'package:voicemate/scenario.dart';
import 'package:voicemate/screens/meter_screen.dart';
import 'package:voicemate/session_controller.dart';
import 'fake_audio_port.dart';

void main() {
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
      find.textContaining('브라우저 처리 설정을 확인할 수 없어 분석을 보류했다.'),
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
