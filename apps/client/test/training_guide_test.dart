import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/app_theme.dart';
import 'package:voicemate/widgets/training_guide.dart';

void main() {
  testWidgets('preparation advances only by choice and can be skipped', (
    tester,
  ) async {
    final selected = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: TrainingGuideScreen(onSelectSection: selected.add),
      ),
    );
    expect(find.text('1 / 4 · 편한 자세'), findsOneWidget);
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('1 / 4 · 편한 자세'), findsOneWidget);
    await tester.tap(find.byKey(const Key('preparation-next')));
    await tester.pumpAndSettle();
    expect(find.text('2 / 4 · 편한 호흡'), findsOneWidget);
    await tester.tap(find.byKey(const Key('preparation-previous')));
    await tester.pumpAndSettle();
    expect(find.text('1 / 4 · 편한 자세'), findsOneWidget);
    await tester.tap(find.byKey(const Key('preparation-skip')));
    await tester.pumpAndSettle();
    expect(find.text('4 / 4 · 훈련 고르기'), findsOneWidget);
    for (var index = 0; index < 3; index++) {
      final target = find.byKey(Key('guide-open-$index'));
      await tester.ensureVisible(target);
      await tester.tap(target);
      expect(selected.last, index);
    }
  });

  testWidgets('guide remains readable and usable at 320px and double text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: TrainingGuideScreen(onSelectSection: (_) {}),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('preparation-skip')));
    await tester.tap(find.byKey(const Key('preparation-skip')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('guide-open-2')));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('회색'), findsOneWidget);
  });
}
