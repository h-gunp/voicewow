import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/app.dart';
import 'package:voicemate/audio/audio_port.dart';
import 'fake_audio_port.dart';

void main() {
  const toggleKey = Key('toggle-noise-reduction');
  final toggle = find.byKey(toggleKey);

  Future<void> startMeter(WidgetTester tester, FakeAudioPort port) async {
    await tester.pumpWidget(VoiceMateApp(audioPort: port));
    await tester.tap(find.byKey(const Key('scenario-quiet')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('start')));
    await tester.tap(find.byKey(const Key('start')));
    await tester.pumpAndSettle();
  }

  testWidgets('noise toggle restarts immediately and clears old input', (
    tester,
  ) async {
    final port = FakeAudioPort();
    await startMeter(tester, port);
    expect(find.text('주변 소음 억제'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
    expect(port.noiseReductionSelections, [true]);
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
    await tester.pump();
    expect(find.text('입력 수준 83.0'), findsOneWidget);
    port.stopGate = Completer<void>();
    port.gate = Completer<void>();
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();
    expect(port.stops, 1);
    expect(port.noiseReductionSelections, [true, false]);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
    expect(find.text('입력 수준 —'), findsOneWidget);
    expect(find.byKey(const Key('input-fill')), findsNothing);
    await tester.ensureVisible(find.text('입력 정보'));
    await tester.tap(find.text('입력 정보'));
    await tester.pumpAndSettle();
    expect(find.textContaining('앱 소음 억제 적용 중'), findsNothing);
    expect(find.textContaining('수신 프레임 0'), findsOneWidget);
    port.send(const AudioEvent.settings({'noiseReductionState': 'disabled'}));
    port.send(const AudioEvent.state(CaptureState.running));
    port.gate!.complete();
    port.stopGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('소음 억제를 끄고 원본 입력을 표시한다.'), findsOneWidget);
    expect(find.textContaining('앱 소음 억제 꺼짐'), findsOneWidget);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();
    expect(port.noiseReductionSelections, [true, false, true]);
  });

  testWidgets('noise choice survives stop restart and scenario change', (
    tester,
  ) async {
    final port = FakeAudioPort();
    await startMeter(tester, port);
    await tester.ensureVisible(find.byKey(const Key('toggle-capture')));
    await tester.tap(find.byKey(const Key('toggle-capture')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();
    expect(port.starts, 1);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.ensureVisible(find.byKey(const Key('toggle-capture')));
    await tester.tap(find.byKey(const Key('toggle-capture')));
    await tester.pump();
    expect(port.noiseReductionSelections, [true, false]);
    await tester.ensureVisible(find.byTooltip('상황 선택으로 이동'));
    await tester.tap(find.byTooltip('상황 선택으로 이동'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('scenario-meeting')));
    await tester.tap(find.byKey(const Key('scenario-meeting')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('start')));
    await tester.tap(find.byKey(const Key('start')));
    await tester.pumpAndSettle();
    expect(port.noiseReductionSelections, [true, false, false]);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
  });

  for (final action in ['stop', 'back', 'dispose']) {
    testWidgets('pending noise toggle cannot revive after $action', (
      tester,
    ) async {
      final port = FakeAudioPort();
      await startMeter(tester, port);
      port.send(const AudioEvent.state(CaptureState.running));
      await tester.pump();
      port.gate = Completer<void>();
      port.stopGate = Completer<void>();
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      expect(port.starts, 2);
      if (action == 'stop') {
        await tester.ensureVisible(find.byKey(const Key('toggle-capture')));
        await tester.tap(find.byKey(const Key('toggle-capture')));
      } else if (action == 'back') {
        await tester.ensureVisible(find.byTooltip('상황 선택으로 이동'));
        await tester.tap(find.byTooltip('상황 선택으로 이동'));
      } else {
        await tester.pumpWidget(const SizedBox());
      }
      if (action != 'dispose') {
        port.send(const AudioEvent.state(CaptureState.running));
      }
      port.gate!.completeError(StateError('cancelled start'));
      port.stopGate!.complete();
      await tester.pumpAndSettle();
      expect(port.starts, 2);
      expect(find.text('입력을 확인하고 있다.'), findsNothing);
      expect(tester.takeException(), isNull);
      if (action == 'stop') {
        expect(find.text('입력이 중지됐다.'), findsOneWidget);
      } else if (action == 'back') {
        expect(find.byKey(const Key('start')), findsOneWidget);
      }
    });
  }
}
