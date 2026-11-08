import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/features/prosody/presentation/prosody_frame_shell.dart';

class _PaintProbe extends LeafRenderObjectWidget {
  const _PaintProbe({super.key});

  @override
  _PaintCounter createRenderObject(BuildContext context) => _PaintCounter();
}

class _PaintCounter extends RenderBox {
  int paints = 0;

  @override
  void performLayout() => size = constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) {
    paints++;
  }
}

void main() {
  testWidgets(
    'loading must paint the frame before its ready message can arrive',
    (tester) async {
      const key = Key('frame');
      Widget screen(bool ready) => MaterialApp(
        home: ProsodyFrameShell(
          ready: ready,
          onRetry: () {},
          frame: const _PaintProbe(key: key),
        ),
      );
      await tester.pumpWidget(screen(false));
      final frame = tester.renderObject<_PaintCounter>(find.byKey(key));
      expect(frame.hasSize, isTrue);
      expect(
        frame.paints,
        greaterThan(0),
        reason:
            'A platform view reaches the DOM only through its painted layer.',
      );
      expect(find.text('높낮이 연습 화면을 준비 중이다.'), findsOneWidget);
      await tester.pumpWidget(screen(true));
      expect(tester.renderObject(find.byKey(key)), same(frame));
      expect(find.text('높낮이 연습 화면을 준비 중이다.'), findsNothing);
    },
  );

  testWidgets('failure keeps the frame alive and offers a working retry', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ProsodyFrameShell(
          ready: false,
          issue: '연결을 확인하고 다시 시도하면 된다.',
          onRetry: () => retries++,
          frame: const _PaintProbe(),
        ),
      ),
    );
    expect(
      tester.renderObject<_PaintCounter>(find.byType(_PaintProbe)).paints,
      greaterThan(0),
    );
    await tester.tap(find.text('다시 불러오기'));
    expect(retries, 1);
  });
}
