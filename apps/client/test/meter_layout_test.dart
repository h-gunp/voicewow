import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/audio/audio_port.dart';
import 'package:voicemate/scenario.dart';
import 'package:voicemate/screens/meter_screen.dart';
import 'package:voicemate/session_controller.dart';
import 'fake_audio_port.dart';

void main() {
  for (final fixture in [
    (900.0, 1.0, true),
    (320.0, 1.0, false),
    (900.0, 2.0, false),
  ]) {
    testWidgets(
      'meter layout at ${fixture.$1}px and ${fixture.$2} text scale',
      (tester) async {
        tester.view.physicalSize = Size(fixture.$1, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final session = SessionController(FakeAudioPort())
          ..selectScenario(Scenario.values.first);
        session.state = CaptureState.running;
        session.analysis = {'state': 'ready', 'speech': 'nonSpeech'};
        addTearDown(session.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(fixture.$2)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: MeterScreen(session: session, onBack: () {}),
                ),
              ),
            ),
          ),
        );
        final gauge = tester.getRect(find.byKey(const Key('gauge-rail')));
        final control = tester.getRect(find.byKey(const Key('toggle-capture')));
        if (fixture.$3) {
          expect(control.left, greaterThan(gauge.right));
        } else {
          expect(control.top, greaterThan(gauge.bottom));
        }
        final stats = tester.getRect(find.textContaining('기본 참고범위'));
        expect(control.bottom, lessThan(stats.top));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
