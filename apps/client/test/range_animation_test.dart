import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/audio/audio_port.dart';
import 'package:voicemate/scenario.dart';
import 'package:voicemate/screens/meter_screen.dart';
import 'package:voicemate/session_controller.dart';
import 'fake_audio_port.dart';

void main() {
  for (final reduceMotion in [false, true]) {
    testWidgets(
      'range moves together and respects reduced motion: $reduceMotion',
      (tester) async {
        final session = SessionController(FakeAudioPort())
          ..selectScenario(Scenario.values.first);
        session.state = CaptureState.running;
        session.settings = {
          'autoGainControl': false,
          'noiseSuppression': false,
          'echoCancellation': false,
        };
        session.analysis = {'state': 'ready', 'offset': 0.0};
        Widget screen() => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: Scaffold(
              body: SingleChildScrollView(
                child: MeterScreen(session: session, onBack: () {}),
              ),
            ),
          ),
        );
        await tester.pumpWidget(screen());
        session.analysis = {'state': 'ready', 'offset': 3.0};
        await tester.pumpWidget(screen());
        await tester.pump(const Duration(milliseconds: 150));
        final lower = tester
            .widget<Text>(find.byKey(const Key('reference-lower')))
            .data!;
        final upper = tester
            .widget<Text>(find.byKey(const Key('reference-upper')))
            .data!;
        final l = double.parse(lower.split(' ').last),
            u = double.parse(upper.split(' ').last);
        expect(u - l, closeTo(22, .01));
        expect(l, reduceMotion ? 56 : inExclusiveRange(53, 56));
        expect(session.effectiveRange.lower, 56);
        if (!reduceMotion) {
          session.analysis = {'state': 'ready', 'offset': 2.0};
          await tester.pumpWidget(screen());
          await tester.pump(const Duration(milliseconds: 600));
          expect(
            tester.widget<Text>(find.byKey(const Key('reference-lower'))).data,
            '하한 55',
          );
        }
        session.dispose();
      },
    );
  }
}
