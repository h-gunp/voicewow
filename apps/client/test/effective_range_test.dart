import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:voicemate/scenario.dart';
import 'package:voicemate/session_controller.dart';
import 'package:voicemate/screens/meter_screen.dart';
import 'package:voicemate/audio/audio_port.dart';
import 'fake_audio_port.dart';

void main() {
  testWidgets(
    'events update both modes and clear adjusted bounds on gap at 320px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
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
      void ready() => port.send(
        const AudioEvent.analysis({
          'state': 'ready',
          'offset': 2.5,
          'speech': 'speech',
          'meterState': 'speech',
          'meterDbfs': -37,
        }),
      );
      ready();
      await tester.pump();
      expect(find.text('하한 55.5'), findsOneWidget);
      expect(find.textContaining('참고 범위 비교 범위 안'), findsOneWidget);
      port.send(
        const AudioEvent.analysis({'state': 'held', 'reason': 'input_gap'}),
      );
      await tester.pump();
      expect(find.text('하한 53'), findsOneWidget);
      expect(find.textContaining('참고 범위 비교'), findsNothing);
      await session.stop();
      session.selectScenario(Scenario.values[2]);
      await session.start();
      port.send(const AudioEvent.state(CaptureState.running));
      port.send(
        const AudioEvent.settings({
          'autoGainControl': false,
          'noiseSuppression': false,
          'echoCancellation': false,
        }),
      );
      ready();
      await tester.pump();
      expect(find.text('하한 70.5'), findsOneWidget);
      expect(find.text('상한 80.5'), findsOneWidget);
      expect(find.textContaining('참고 범위 비교 범위 안'), findsOneWidget);
      expect(tester.takeException(), isNull);
      session.dispose();
    },
  );
  testWidgets('displayed equal values do not report above the limit', (
    tester,
  ) async {
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
      'offset': 2.51,
      'speech': 'speech',
      'meterState': 'speech',
      'meterDbfs': -36.48,
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
    expect(find.text('입력 수준 77.5'), findsOneWidget);
    expect(find.text('상한 77.5'), findsOneWidget);
    expect(find.textContaining('참고 범위 비교 범위 안'), findsOneWidget);
    session.analysis = {...session.analysis, 'meterDbfs': -36.44};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MeterScreen(session: session, onBack: () {}),
          ),
        ),
      ),
    );
    expect(find.textContaining('참고 범위 비교 상한 초과'), findsOneWidget);
    session.dispose();
  });
  testWidgets('gauge and comparison use the same adjusted bounds', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final session = SessionController(FakeAudioPort())
      ..selectScenario(Scenario.values.first);
    session.settings = {
      'autoGainControl': false,
      'noiseSuppression': false,
      'echoCancellation': false,
    };
    session.analysis = {'state': 'ready', 'offset': 2.5};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MeterScreen(session: session, onBack: () {}),
          ),
        ),
      ),
    );
    expect(find.text('하한 55.5'), findsOneWidget);
    expect(find.text('상한 77.5'), findsOneWidget);
    expect(find.textContaining('환경 적응 참고범위 55.5–77.5'), findsOneWidget);
    final rail = tester.getRect(find.byKey(const Key('gauge-rail')));
    final upper = tester.getRect(find.byKey(const Key('reference-line-77.5')));
    final lower = tester.getRect(find.byKey(const Key('reference-line-55.5')));
    expect(
      upper.center.dy,
      closeTo(rail.top + (1 - 77.5 / 120) * rail.height, .01),
    );
    expect(
      lower.center.dy,
      closeTo(rail.top + (1 - 55.5 / 120) * rail.height, .01),
    );
    expect(find.bySemanticsLabel(RegExp('하한 55.5, 상한 77.5')), findsOneWidget);
    semantics.dispose();
    session.dispose();
  });
  test('effective range applies only a valid ready offset', () {
    final session = SessionController(FakeAudioPort())
      ..selectScenario(Scenario.values.first);
    session.settings = {
      'autoGainControl': false,
      'noiseSuppression': false,
      'echoCancellation': false,
    };
    session.analysis = {'state': 'ready', 'offset': 2.5};
    expect(session.effectiveRange.lower, 55.5);
    expect(session.effectiveRange.upper, 77.5);
    expect(session.effectiveRange.adjusted, isTrue);
    session.settings = {'autoGainControl': false, 'noiseSuppression': false};
    expect(session.effectiveRange.adjusted, isFalse);
    session.settings = {
      'autoGainControl': true,
      'noiseSuppression': false,
      'echoCancellation': false,
    };
    expect(session.effectiveRange.adjusted, isFalse);
    session.settings = {
      'autoGainControl': false,
      'noiseSuppression': false,
      'echoCancellation': false,
    };
    for (final data in [
      {'state': 'held', 'offset': 2.5},
      {'state': 'ready', 'offset': 4.0},
      {'state': 'ready', 'offset': double.nan},
      {'state': 'ready', 'offset': double.infinity},
      {'state': 'ready', 'offset': -0.1},
      {'state': 'ready'},
    ]) {
      session.analysis = data;
      expect(session.effectiveRange.lower, 53);
      expect(session.effectiveRange.upper, 75);
      expect(session.effectiveRange.adjusted, isFalse);
    }
    session.analysis = {'state': 'ready', 'offset': 2.0};
    session.selectScenario(Scenario.values[2]);
    expect(session.effectiveRange.lower, 70);
    expect(session.effectiveRange.upper, 80);
    session.analysis = {'state': 'held', 'reason': 'input_gap', 'offset': 2.0};
    expect(session.effectiveRange.lower, 68);
    expect(session.effectiveRange.upper, 78);
    session.dispose();
  });
}
