import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/app_theme.dart';
import 'package:voicemate/widgets/training_guide.dart';

void main() {
  testWidgets('guide explains each feature and opens the selected training', (
    tester,
  ) async {
    final selected = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: TrainingGuideScreen(onSelectSection: selected.add),
      ),
    );
    expect(find.text('기능별 사용 방법'), findsOneWidget);
    expect(find.textContaining('주변 환경음 듣기'), findsOneWidget);
    expect(find.textContaining('회색은 판단이 불확실'), findsOneWidget);
    expect(find.textContaining('약 378MB'), findsOneWidget);
    expect(find.textContaining('내 대본으로도 연습'), findsOneWidget);
    expect(find.byKey(const Key('preparation-next')), findsNothing);
    expect(selected, isEmpty);
    for (var index = 0; index < 3; index++) {
      final target = find.byKey(Key('guide-open-$index'));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(selected.last, index);
    }
    expect(selected, [0, 1, 2]);
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
    for (var index = 0; index < 3; index++) {
      final target = find.byKey(Key('guide-open-$index'));
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      expect(target.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    expect(find.textContaining('회색'), findsOneWidget);
  });
}
