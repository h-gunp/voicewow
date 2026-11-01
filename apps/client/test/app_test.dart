import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/app.dart';
import 'package:voicemate/app_theme.dart';
import 'package:voicemate/audio/audio_port.dart';
import 'package:voicemate/scenario.dart';
import 'package:voicemate/widgets/volume_gauge.dart';
import 'fake_audio_port.dart';

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  for (final scale in [1.0, 2.0])
    testWidgets('reference geometry uses exact scale at $scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Center(
              child: SizedBox(
                width: 400,
                child: VolumeGauge(scenario: Scenario.values.first),
              ),
            ),
          ),
        ),
      );
      final rail = tester.getRect(find.byKey(const Key('gauge-rail')));
      for (final value in [53, 75]) {
        final marker = tester.getRect(find.byKey(Key('reference-line-$value')));
        expect(
          marker.center.dy,
          closeTo(rail.bottom - rail.height * value / 120, .01),
        );
      }
    });
  testWidgets('situation cards expose and execute accessibility tap', (
    tester,
  ) async {
    await tester.pumpWidget(VoiceMateApp(audioPort: FakeAudioPort()));
    final node = tester.getSemantics(find.byKey(const Key('scenario-quiet')));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('start'))).onPressed,
      isNotNull,
    );
  });
  testWidgets('late back navigation cannot hide a newly started capture', (
    tester,
  ) async {
    final port = FakeAudioPort();
    await tester.pumpWidget(VoiceMateApp(audioPort: port));
    await tester.tap(find.byKey(const Key('scenario-quiet')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('start')));
    await tester.tap(find.byKey(const Key('start')));
    await tester.pumpAndSettle();
    port.send(const AudioEvent.state(CaptureState.running));
    await tester.pump();
    port.stopGate = Completer<void>();
    await tester.ensureVisible(find.byTooltip('상황 선택으로 이동'));
    await tester.tap(find.byTooltip('상황 선택으로 이동'));
    await tester.pumpAndSettle();
    final start = find.byKey(const Key('start'));
    final retry = find.byKey(const Key('toggle-capture'));
    final available = start.evaluate().isNotEmpty ? start : retry;
    await tester.ensureVisible(available);
    await tester.tap(available);
    await tester.pump();
    port.send(const AudioEvent.state(CaptureState.running));
    port.stopGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('입력을 확인하고 있다.'), findsOneWidget);
    expect(find.byKey(const Key('toggle-capture')), findsOneWidget);
  });
  testWidgets('selection, start, genuine level, stop, restart and error', (
    tester,
  ) async {
    final port = FakeAudioPort();
    await tester.pumpWidget(VoiceMateApp(audioPort: port));
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('start'))).onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('scenario-quiet')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('start')));
    await tester.tap(find.byKey(const Key('start')));
    await tester.pumpAndSettle();
    expect(port.starts, 1);
    expect(find.text('마이크 권한을 확인한다.'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('마이크 권한을 확인한다.')).dy,
      greaterThanOrEqualTo(0),
    );
    port.send(const AudioEvent.state(CaptureState.running));
    port.send(
      const AudioEvent.level(
        rms: .5,
        dbfs: -6,
        normalized: .925,
        sampleCount: 4800,
      ),
    );
    port.send(
      const AudioEvent.analysis({
        'state': 'ready',
        'speech': 'speech',
        'meterState': 'speech',
        'meterDbfs': -6.0,
      }),
    );
    await tester.pump();
    expect(find.text('입력 수준 108.0'), findsOneWidget);
    expect(find.byKey(const Key('input-fill')), findsOneWidget);
    expect(find.byKey(const Key('reference-upper')), findsOneWidget);
    for (final word in ['적정', '더 크게', '더 작게', 'dBA'])
      expect(find.textContaining(word), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('toggle-capture')));
    await tester.tap(find.byKey(const Key('toggle-capture')));
    await tester.pumpAndSettle();
    expect(port.stops, 1);
    expect(find.byKey(const Key('input-fill')), findsNothing);
    await tester.tap(find.byKey(const Key('toggle-capture')));
    await tester.pump();
    expect(port.starts, 2);
    port.send(
      const AudioEvent.state(CaptureState.error, reason: 'permission_denied'),
    );
    await tester.pump();
    expect(find.text('마이크 권한이 필요하다.'), findsOneWidget);
  });

  testWidgets(
    '320x568 with 200 percent text remains scrollable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = FakeAudioPort();
      await tester.pumpWidget(
        VoiceMateApp(audioPort: port, textScaler: TextScaler.linear(2)),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('scenario-quiet')));
      await tester.tap(find.byKey(const Key('scenario-quiet')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('start')));
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('toggle-capture')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('toggle-capture')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('toggle-capture')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('reference labels do not overlap with 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      VoiceMateApp(
        audioPort: FakeAudioPort(),
        textScaler: TextScaler.linear(2),
      ),
    );
    await tester.ensureVisible(find.byKey(const Key('scenario-meeting')));
    await tester.tap(find.byKey(const Key('scenario-meeting')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('start')));
    await tester.tap(find.byKey(const Key('start')));
    await tester.pumpAndSettle();
    final upper = tester.getRect(find.byKey(const Key('reference-upper'))),
        lower = tester.getRect(find.byKey(const Key('reference-lower')));
    expect(upper.bottom, lessThanOrEqualTo(lower.top));
    expect(tester.takeException(), isNull);
  });

  test('four scenario reference ranges stay fixed', () {
    expect(Scenario.values.map((s) => [s.referenceLower, s.referenceUpper]), [
      [53, 75],
      [58, 80],
      [68, 78],
      [65, 75],
    ]);
  });

  for (final fixture in [
    ('quiet', 53, 75, -61.0),
    ('noisy', 58, 80, -56.0),
    ('meeting', 68, 78, -46.0),
    ('auditorium', 65, 75, -49.0),
  ]) {
    testWidgets('${fixture.$1} keeps red limits on the live input bar', (
      tester,
    ) async {
      final port = FakeAudioPort();
      await tester.pumpWidget(VoiceMateApp(audioPort: port));
      await tester.tap(find.byKey(Key('scenario-${fixture.$1}')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('start')));
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();
      expect(find.text('하한 ${fixture.$2}'), findsOneWidget);
      expect(find.text('상한 ${fixture.$3}'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byKey(const Key('configure-range')), findsNothing);
      expect(find.byKey(const Key('accept-unknown-gain')), findsNothing);
      port.send(const AudioEvent.state(CaptureState.running));
      port.send(
        AudioEvent.level(
          rms: .03,
          dbfs: fixture.$4,
          normalized: .5,
          sampleCount: 4800,
        ),
      );
      port.send(
        AudioEvent.analysis({
          'state': 'ready',
          'speech': 'speech',
          'meterState': 'speech',
          'meterDbfs': fixture.$4,
        }),
      );
      await tester.pump();
      expect(find.text('입력 수준 ${fixture.$2}.0'), findsOneWidget);
      await tester.pumpAndSettle();
      final fill = tester.getRect(find.byKey(const Key('input-fill')));
      final lower = tester.getRect(
        find.byKey(Key('reference-line-${fixture.$2}')),
      );
      expect(fill.top, closeTo(lower.center.dy, .01));
      final label = tester.widget<Text>(find.text('하한 ${fixture.$2}'));
      expect(label.style!.color, red);
      await tester.ensureVisible(find.byKey(const Key('toggle-capture')));
      await tester.tap(find.byKey(const Key('toggle-capture')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('input-fill')), findsNothing);
      expect(find.text('하한 ${fixture.$2}'), findsOneWidget);
      expect(find.text('상한 ${fixture.$3}'), findsOneWidget);
    });
  }

  testWidgets('speech levels clamp while missing input has no fill', (
    tester,
  ) async {
    final port = FakeAudioPort();
    await tester.pumpWidget(VoiceMateApp(audioPort: port));
    await tester.tap(find.byKey(const Key('scenario-quiet')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('start')));
    await tester.tap(find.byKey(const Key('start')));
    await tester.pumpAndSettle();
    port.send(const AudioEvent.state(CaptureState.running));
    for (final fixture in [
      (-50.0, '64.0'),
      (-20.0, '94.0'),
      (-9.0, '105.0'),
      (0.0, '114.0'),
      (5.0, '119.0'),
      (6.0, '120.0'),
      (15.0, '120.0'),
      (16.0, '120.0'),
      (26.0, '120.0'),
      (30.0, '120.0'),
      (-79.0, '35.0'),
      (-100.0, '14.0'),
      (-104.0, '10.0'),
      (-113.0, '1.0'),
      (-114.0, '0.0'),
      (-120.0, '0.0'),
      (null, '—'),
    ]) {
      port.send(
        AudioEvent.level(
          rms: fixture.$1 == null ? 0 : .03,
          dbfs: fixture.$1,
          normalized: .5,
          sampleCount: 4800,
        ),
      );
      port.send(
        AudioEvent.analysis({
          'state': 'ready',
          'speech': 'speech',
          'meterState': 'speech',
          'meterDbfs': fixture.$1,
        }),
      );
      await tester.pump();
      expect(find.text('입력 수준 ${fixture.$2}'), findsOneWidget);
      expect(
        find.byKey(const Key('input-fill')),
        fixture.$1 == null ? findsNothing : findsOneWidget,
      );
    }
    port.send(
      const AudioEvent.state(CaptureState.error, reason: 'device_missing'),
    );
    await tester.pump();
    expect(find.byKey(const Key('input-fill')), findsNothing);
    expect(find.text('입력 수준 —'), findsOneWidget);
    expect(find.text('하한 53'), findsOneWidget);
    expect(find.text('상한 75'), findsOneWidget);
  });

  for (final agc in [null, false, true]) {
    testWidgets('AGC $agc neither requires registration nor blocks input', (
      tester,
    ) async {
      final port = FakeAudioPort();
      await tester.pumpWidget(VoiceMateApp(audioPort: port));
      await tester.tap(find.byKey(const Key('scenario-quiet')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('start')));
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();
      port.send(AudioEvent.settings({'autoGainControl': agc}));
      port.send(const AudioEvent.state(CaptureState.running));
      port.send(
        const AudioEvent.level(
          rms: .03,
          dbfs: -31,
          peak: .2,
          normalized: .5,
          sampleCount: 4800,
        ),
      );
      await tester.pump();
      expect(find.text('입력 수준 —'), findsOneWidget);
      expect(find.text('하한 53'), findsOneWidget);
      expect(find.text('상한 75'), findsOneWidget);
      expect(find.byKey(const Key('configure-range')), findsNothing);
      expect(find.byKey(const Key('accept-unknown-gain')), findsNothing);
      expect(find.textContaining('등록'), findsNothing);
    });
  }

  for (final reason in ['insecure_context', 'unsupported', 'device_changed']) {
    testWidgets('$reason keeps mobile recovery guidance without registration', (
      tester,
    ) async {
      final port = FakeAudioPort();
      await tester.pumpWidget(VoiceMateApp(audioPort: port));
      await tester.tap(find.byKey(const Key('scenario-quiet')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('start')));
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();
      port.send(
        AudioEvent.state(
          reason == 'device_changed' ? CaptureState.idle : CaptureState.error,
          reason: reason,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('등록'), findsNothing);
      expect(find.textContaining('PC의 Chrome'), findsNothing);
      if (reason == 'insecure_context') {
        expect(find.textContaining('HTTPS 주소'), findsOneWidget);
      } else if (reason == 'unsupported') {
        expect(find.textContaining('최신 Safari 또는 Chrome'), findsOneWidget);
      } else {
        expect(find.textContaining('입력 장치 구성이 바뀌었다'), findsOneWidget);
        expect(find.textContaining('다시 시작'), findsWidgets);
      }
      expect(find.text('하한 53'), findsOneWidget);
      expect(find.text('상한 75'), findsOneWidget);
    });
  }

  for (final scale in [1.0, 2.0]) {
    for (final fixture in [
      (
        CaptureState.requesting,
        'loading',
        '소음 억제를 준비하고 있다.',
        '입력 준비가 끝나면 측정을 시작한다.',
        '준비 중',
        '원본 입력 — dBFS',
      ),
      (
        CaptureState.running,
        'active',
        '입력을 확인하고 있다.',
        '주변 소음을 줄인 입력이다. 다른 사람의 목소리가 남을 수 있다.',
        '적용 중',
        '소음 억제 후 입력 -31.0 dBFS',
      ),
      (
        CaptureState.running,
        'disabled',
        '입력을 확인하고 있다.',
        '소음 억제가 꺼져 발화 막대를 표시하지 않는다.',
        '꺼짐',
        '원본 입력 -31.0 dBFS',
      ),
      (
        CaptureState.running,
        'unavailable',
        '입력을 확인하고 있다.',
        '소음 억제를 사용할 수 없어 발화 막대를 표시하지 않는다.',
        '사용 불가',
        '원본 입력 -31.0 dBFS',
      ),
    ]) {
      testWidgets(
        'noise reduction ${fixture.$2} explains its input at text scale $scale',
        (tester) async {
          tester.view.physicalSize = const Size(320, 568);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final port = FakeAudioPort();
          await tester.pumpWidget(
            VoiceMateApp(audioPort: port, textScaler: TextScaler.linear(scale)),
          );
          await tester.ensureVisible(find.byKey(const Key('scenario-quiet')));
          await tester.tap(find.byKey(const Key('scenario-quiet')));
          await tester.pump();
          await tester.ensureVisible(find.byKey(const Key('start')));
          await tester.tap(find.byKey(const Key('start')));
          await tester.pumpAndSettle();
          port.send(
            AudioEvent.settings({
              'noiseReductionState': fixture.$2,
              'noiseSuppression': false,
            }),
          );
          port.send(AudioEvent.state(fixture.$1));
          if (fixture.$1 == CaptureState.running) {
            port.send(
              const AudioEvent.level(
                rms: .03,
                dbfs: -31,
                normalized: .5,
                sampleCount: 4800,
              ),
            );
          }
          await tester.pumpAndSettle();
          expect(find.text(fixture.$3), findsOneWidget);
          expect(find.text(fixture.$4), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('입력 정보'));
          await tester.tap(find.text('입력 정보'));
          await tester.pumpAndSettle();
          expect(find.textContaining('앱 소음 억제 ${fixture.$5}'), findsOneWidget);
          expect(find.textContaining('브라우저 잡음 억제 꺼짐'), findsOneWidget);
          expect(find.textContaining(fixture.$6), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.byKey(const Key('toggle-capture')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('toggle-capture')).hitTestable(),
            findsOneWidget,
          );
        },
      );
    }
  }

  for (final terminalState in [CaptureState.idle, CaptureState.error]) {
    testWidgets('noise reduction active details clear after $terminalState', (
      tester,
    ) async {
      final port = FakeAudioPort();
      await tester.pumpWidget(VoiceMateApp(audioPort: port));
      await tester.tap(find.byKey(const Key('scenario-quiet')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('start')));
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();
      port.send(const AudioEvent.settings({'noiseReductionState': 'active'}));
      port.send(const AudioEvent.state(CaptureState.running));
      port.send(
        const AudioEvent.level(
          rms: .03,
          dbfs: -31,
          normalized: .5,
          sampleCount: 4800,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('입력 정보'));
      await tester.tap(find.text('입력 정보'));
      await tester.pumpAndSettle();
      expect(find.textContaining('앱 소음 억제 적용 중'), findsOneWidget);
      if (terminalState == CaptureState.idle) {
        await tester.ensureVisible(find.byKey(const Key('toggle-capture')));
        await tester.tap(find.byKey(const Key('toggle-capture')));
      } else {
        port.send(
          const AudioEvent.state(
            CaptureState.error,
            reason: 'noise_reduction_failed',
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(find.textContaining('앱 소음 억제 미사용'), findsOneWidget);
      expect(find.textContaining('소음 억제 후 입력'), findsNothing);
      expect(find.textContaining('주변 소음을 줄인 입력'), findsNothing);
      expect(find.text('입력 수준 —'), findsOneWidget);
      expect(find.byKey(const Key('input-fill')), findsNothing);
      if (terminalState == CaptureState.error) {
        expect(find.text('소음 억제 중 문제가 발생했다. 다시 시작한다.'), findsOneWidget);
      }
    });
  }
}
