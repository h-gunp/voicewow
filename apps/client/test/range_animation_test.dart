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
        session.analysis = {
          'state': 'ready',
          'calibrationValid': true,
          'provenance': 'verified',
          'offset': 0.0,
        };
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
        session.analysis = {
          'state': 'ready',
          'calibrationValid': true,
          'provenance': 'verified',
          'offset': 3.0,
        };
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
          session.analysis = {
            'state': 'ready',
            'calibrationValid': true,
            'provenance': 'verified',
            'offset': 2.0,
          };
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

  testWidgets(
    'comparison is hidden during a transition and resumes at the actual range',
    (tester) async {
      final session = SessionController(FakeAudioPort())
        ..selectScenario(Scenario.values.first);
      session.state = CaptureState.running;
      session.settings = {
        'autoGainControl': false,
        'noiseSuppression': false,
        'echoCancellation': false,
      };
      session.analysis = {
        'state': 'ready',
        'calibrationValid': true,
        'provenance': 'verified',
        'offset': 0.0,
        'speech': 'speech',
        'meterState': 'speech',
        'meterDbfs': -60.2,
      };
      Widget screen() => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MeterScreen(session: session, onBack: () {}),
          ),
        ),
      );
      await tester.pumpWidget(screen());
      expect(find.textContaining('참고 범위 비교 범위 안'), findsOneWidget);
      session.analysis = {...session.analysis, 'offset': 2.0};
      await tester.pumpWidget(screen());
      await tester.pump(const Duration(milliseconds: 100));
      expect(session.effectiveRange.lower, 55);
      expect(find.textContaining('참고 범위 비교'), findsNothing);
      session.analysis = {...session.analysis, 'offset': 3.0};
      await tester.pumpWidget(screen());
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('참고 범위 비교'), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('참고 범위 비교 하한 미만'), findsOneWidget);
      session.dispose();
    },
  );

  testWidgets(
    'reduced motion and invalidated input compare immediately against the current range',
    (tester) async {
      final session = SessionController(FakeAudioPort())
        ..selectScenario(Scenario.values.first);
      session.state = CaptureState.running;
      session.settings = {
        'autoGainControl': false,
        'noiseSuppression': false,
        'echoCancellation': false,
      };
      session.analysis = {
        'state': 'ready',
        'calibrationValid': true,
        'provenance': 'verified',
        'offset': 0.0,
        'speech': 'speech',
        'meterState': 'speech',
        'meterDbfs': -60.2,
      };
      Widget screen() => MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SingleChildScrollView(
              child: MeterScreen(session: session, onBack: () {}),
            ),
          ),
        ),
      );
      await tester.pumpWidget(screen());
      session.analysis = {...session.analysis, 'offset': 2.0};
      await tester.pumpWidget(screen());
      await tester.pump();
      expect(find.textContaining('참고 범위 비교 하한 미만'), findsOneWidget);
      session.analysis = {
        ...session.analysis,
        'state': 'failed',
        'calibrationValid': false,
        'reason': 'input_gap',
      };
      await tester.pumpWidget(screen());
      await tester.pump();
      expect(session.effectiveRange.lower, 53);
      expect(find.textContaining('참고 범위 비교 범위 안'), findsOneWidget);
      session.dispose();
    },
  );
}
