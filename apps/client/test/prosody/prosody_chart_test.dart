import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/features/prosody/audio/audio_analysis.dart';
import 'package:voicemate/features/prosody/widgets/prosody_chart.dart';

AudioFrame point(double t, double? pitch) => AudioFrame(
  time: t,
  pitchHz: pitch == null ? null : 180,
  rmsDb: -20,
  active: pitch != null,
  relativePitch: pitch,
  relativeDb: pitch == null ? null : 0,
);

void main() {
  testWidgets(
    'a phone-sized live chart handles isolated measurements, a pause and semantic labels',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final reference = AudioAnalysis(
        duration: 1.2,
        frames: [point(0, -2), point(.4, 2), point(.8, null), point(1.2, 0)],
      );
      final trace = [
        point(0, 0),
        point(.04, null),
        point(.08, 2),
        point(.12, null),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: ProsodyChart(
                reference: reference,
                trace: trace,
                live: true,
                progress: .12,
                domainSeconds: 1.5,
                scaleBound: 5,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('가이드'), findsOneWidget);
      expect(find.text('내 목소리'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('상대적인 음높이 그래프.*녹음 경과 시간')),
        findsOneWidget,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: ProsodyChart(
                reference: reference,
                trace: [point(0, 0), point(.04, 25)],
                live: true,
                progress: 2.0,
                domainSeconds: .1,
                scaleBound: 1,
              ),
            ),
          ),
        ),
      );
      expect(
        tester.takeException(),
        isNull,
        reason:
            'small scale overrides and later progress must remain paintable',
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'a selected final interval is described as time rather than a recognized word',
    (tester) async {
      final semantics = tester.ensureSemantics();
      const selected = Segment(
        label: '선택 구간 전체',
        start: 0,
        end: .3,
        userStart: 0,
        userEnd: .3,
        pairs: 10,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProsodyChart(
              reference: AudioAnalysis(
                duration: .3,
                frames: [point(0, 1), point(.3, -2)],
              ),
              trace: [point(0, 2), point(.3, -1)],
              selected: selected,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel(RegExp('선택한 구간: 선택 구간 전체')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('마지막 음절|정상|점수')), findsNothing);
      semantics.dispose();
    },
  );
}
