import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:voicemate/features/prosody/widgets/prosody_chart.dart';
import 'package:voicemate/app_theme.dart';

void main() {
  test('app theme uses the bundled Korean font and readable default text', () {
    final theme = buildAppTheme();
    expect(theme.textTheme.bodyLarge?.fontFamily, 'Pretendard');
    expect(theme.textTheme.bodyLarge?.fontSize, greaterThanOrEqualTo(16));
    expect(theme.textTheme.bodyMedium?.fontSize, greaterThanOrEqualTo(14));
  });

  testWidgets(
    'chart expands with larger system text and retains accessible description',
    (tester) async {
      Widget chart(double scale) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: const Scaffold(body: ProsodyChart()),
        ),
      );
      await tester.pumpWidget(chart(1));
      final painter = find.descendant(
        of: find.byType(ProsodyChart),
        matching: find.byType(CustomPaint),
      );
      final height = tester.getSize(painter).height;
      await tester.pumpWidget(chart(2));
      expect(tester.getSize(painter).height, height * 2);
      expect(find.bySemanticsLabel(RegExp('그래프')), findsWidgets);
    },
  );
  testWidgets('font and model license texts are bundled locally', (
    tester,
  ) async {
    expect(
      await rootBundle.loadString('assets/fonts/OFL.txt'),
      contains('SIL OPEN FONT LICENSE'),
    );
    expect(
      await rootBundle.loadString(
        'web/prosody/vendor/supertonic/LICENSE-model.txt',
      ),
      contains('BigScience Open RAIL-M License'),
    );
  });
}
