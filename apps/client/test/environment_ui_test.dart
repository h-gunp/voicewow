import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/audio/audio_port.dart';
import 'package:voicemate/scenario.dart';
import 'package:voicemate/screens/meter_screen.dart';
import 'package:voicemate/session_controller.dart';
import 'fake_audio_port.dart';

void main() {
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
