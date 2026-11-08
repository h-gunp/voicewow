import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/app.dart';
import 'package:voicemate/text_size_preferences.dart';

import 'fake_audio_port.dart';

class _MemoryTextSizeStore implements TextSizeStore {
  AppTextSize value = AppTextSize.basic;
  Completer<AppTextSize>? pendingLoad;
  Completer<void>? pendingFirstSave;
  bool failSave = false;
  final writes = <AppTextSize>[];

  @override
  Future<AppTextSize> load() async {
    final pending = pendingLoad;
    return pending == null ? value : await pending.future;
  }

  @override
  Future<void> save(AppTextSize next) async {
    if (failSave) throw StateError('Storage unavailable');
    writes.add(next);
    if (writes.length == 1) await pendingFirstSave?.future;
    value = next;
  }
}

Future<void> _chooseSize(WidgetTester tester, AppTextSize size) async {
  await tester.tap(find.byKey(const Key('text-size-control')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(Key('text-size-${size.name}')));
  await tester.tap(find.byKey(Key('text-size-${size.name}')));
  await tester.pumpAndSettle();
}

double _fontSize(WidgetTester tester) => MediaQuery.textScalerOf(
  tester.element(find.byKey(const Key('scenario-quiet'))),
).scale(16);

void main() {
  testWidgets('text size persists and composes with injected system scaling', (
    tester,
  ) async {
    final store = _MemoryTextSizeStore();
    Widget app(Key key) => VoiceMateApp(
      key: key,
      audioPort: FakeAudioPort(),
      textScaler: const TextScaler.linear(1.2),
      textSizeStore: store,
    );
    await tester.pumpWidget(app(const ValueKey(1)));
    await tester.pumpAndSettle();
    await _chooseSize(tester, AppTextSize.larger);
    expect(_fontSize(tester), closeTo(28.8, .001));
    expect(store.writes, [AppTextSize.larger]);

    await tester.pumpWidget(app(const ValueKey(2)));
    await tester.pumpAndSettle();
    expect(_fontSize(tester), closeTo(28.8, .001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('late preference load cannot replace an early user choice', (
    tester,
  ) async {
    final pending = Completer<AppTextSize>();
    final store = _MemoryTextSizeStore()..pendingLoad = pending;
    await tester.pumpWidget(
      VoiceMateApp(audioPort: FakeAudioPort(), textSizeStore: store),
    );
    expect(find.byKey(const Key('scenario-quiet')), findsOneWidget);
    await _chooseSize(tester, AppTextSize.large);
    pending.complete(AppTextSize.basic);
    await tester.pumpAndSettle();
    expect(_fontSize(tester), 20);
    expect(store.value, AppTextSize.large);
  });

  testWidgets('successive choices are saved in order', (tester) async {
    final pending = Completer<void>();
    final store = _MemoryTextSizeStore()..pendingFirstSave = pending;
    await tester.pumpWidget(
      VoiceMateApp(audioPort: FakeAudioPort(), textSizeStore: store),
    );
    await _chooseSize(tester, AppTextSize.large);
    await _chooseSize(tester, AppTextSize.larger);
    expect(store.writes, [AppTextSize.large]);
    pending.complete();
    await tester.pumpAndSettle();
    expect(store.writes, [AppTextSize.large, AppTextSize.larger]);
    expect(store.value, AppTextSize.larger);
  });

  testWidgets('failed storage keeps chosen text size usable', (tester) async {
    final store = _MemoryTextSizeStore()..failSave = true;
    await tester.pumpWidget(
      VoiceMateApp(audioPort: FakeAudioPort(), textSizeStore: store),
    );
    await _chooseSize(tester, AppTextSize.large);
    expect(_fontSize(tester), 20);
    await tester.tap(find.byKey(const Key('text-size-control')));
    await tester.pumpAndSettle();
    expect(find.textContaining('저장하지 못했다'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'small display keeps size controls usable with 200 percent text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        VoiceMateApp(
          audioPort: FakeAudioPort(),
          textSizeStore: _MemoryTextSizeStore(),
          textScaler: const TextScaler.linear(2),
        ),
      );
      await _chooseSize(tester, AppTextSize.larger);
      expect(_fontSize(tester), 48);
      expect(
        find.byKey(const Key('text-size-control')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('open-training-guide')).hitTestable(),
        findsOneWidget,
      );
      await _chooseSize(tester, AppTextSize.basic);
      expect(_fontSize(tester), 32);
      expect(tester.takeException(), isNull);
    },
  );
}
