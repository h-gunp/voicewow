import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/scenario.dart';
import 'package:voicemate/widgets/volume_gauge.dart';

void main() {
  testWidgets(
    'brief presentation syllables immediately reach measured height after silence',
    (tester) async {
      Future<void> show(double? level) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 500,
              child: VolumeGauge(
                scenario: Scenario.values[2],
                displayLevel: level,
              ),
            ),
          ),
        ),
      );
      await show(72);
      final initialHeight = tester
          .getSize(find.byKey(const Key('input-fill')))
          .height;
      expect(initialHeight, greaterThan(0));
      await tester.pumpAndSettle();
      final settledHeight = tester
          .getSize(find.byKey(const Key('input-fill')))
          .height;
      expect(initialHeight, closeTo(settledHeight, .01));
      await show(null);
      expect(find.byKey(const Key('input-fill')), findsNothing);
      await show(72);
      expect(
        tester.getSize(find.byKey(const Key('input-fill'))).height,
        closeTo(settledHeight, .01),
      );
    },
  );
}
