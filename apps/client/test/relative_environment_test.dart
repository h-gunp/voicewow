import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:voicemate/audio/audio_port.dart';
import 'package:voicemate/screens/meter_screen.dart';
import 'package:voicemate/scenario.dart';
import 'package:voicemate/session_controller.dart';
import 'fake_audio_port.dart';

void main() {
  test(
    'relative input requires matching provenance and only missing settings',
    () {
      final session = SessionController(FakeAudioPort())
        ..selectScenario(Scenario.values.first);
      session.state = CaptureState.running;
      session.settings = {'echoCancellation': false};
      session.analysis = {
        'state': 'ready',
        'calibrationValid': true,
        'offset': 2.0,
        'provenance': 'relative_input',
      };
      expect(session.effectiveRange.lower, 55);
      expect(session.effectiveRange.adjusted, isTrue);
      for (final bad in [true, 'all', null, 0]) {
        session.settings = {'echoCancellation': bad};
        expect(session.effectiveRange.adjusted, isFalse);
      }
      session.state = CaptureState.running;
      session.settings = {'echoCancellation': false};
      session.analysis = {
        'state': 'ready',
        'calibrationValid': true,
        'offset': 2.0,
        'provenance': 'verified',
      };
      expect(session.effectiveRange.adjusted, isFalse);
      session.dispose();
    },
  );
  testWidgets(
    'relative provenance reaches range and accessible UI without claiming voice level',
    (tester) async {
      final port = FakeAudioPort();
      final session = SessionController(port)
        ..selectScenario(Scenario.values.first);
      await session.start();
      port.send(const AudioEvent.state(CaptureState.running));
      port.send(const AudioEvent.settings({'echoCancellation': false}));
      port.send(
        const AudioEvent.analysis({
          'state': 'ready',
          'calibrationValid': true,
          'offset': 2.0,
          'provenance': 'relative_input',
          'speech': 'nonSpeech',
          'voiceDbfs': null,
          'noiseDbfs': -40.0,
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
      expect(find.text('주변 환경음의 상대 입력 기준'), findsOneWidget);
      expect(find.textContaining('고정 참고범위 55.0–77.0'), findsOneWidget);
      expect(find.textContaining('발화 수준 추정'), findsNothing);
      expect(find.textContaining('주변 잡음 추정'), findsNothing);
      expect(session.effectiveRange.lower, 55);
      expect(SessionController.inputLevelOffset, 114);
      session.dispose();
    },
  );

  testWidgets('diagnostics keep input units and license access', (
    tester,
  ) async {
    final session = SessionController(FakeAudioPort())
      ..selectScenario(Scenario.values.first);
    session.state = CaptureState.running;
    session.settings = {
      'echoCancellation': false,
      'noiseReductionState': 'active',
    };
    session.analysis = {
      'state': 'ready',
      'calibrationValid': true,
      'offset': 0.0,
      'provenance': 'relative_input',
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MeterScreen(session: session, onBack: () {}),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('앱 정보 · 진단'));
    await tester.tap(find.text('앱 정보 · 진단'));
    await tester.pumpAndSettle();
    expect(find.textContaining('소음 억제 후 입력 — dBFS'), findsOneWidget);
    await tester.tap(find.text('오픈소스 · 모델 이용 조건'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    session.dispose();
  });
}
