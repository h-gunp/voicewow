// Manual native UI preview, without microphone or platform audio plugins.
// flutter test tools/preview_prosody.dart
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/app.dart';
import 'package:voicemate/features/prosody/practice_session.dart';
import 'package:voicemate/features/prosody/services/device_audio.dart';
import 'package:voicemate/features/prosody/widgets/prosody_chart.dart';

class PreviewAudio extends DeviceAudioService {
  @override
  Stream<String> get errors => const Stream.empty();
  @override
  Future<String> storeAudio(
    Uint8List bytes, {
    String name = 'audio.wav',
  }) async => '$name.wav';
  @override
  Future<void> stopPlayback() async {}
}

void main() {
  testWidgets('capture the native phone layout for manual review', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      // The preview can use the Mac's Korean font without bundling it in the app.
      final korean = File('/System/Library/Fonts/AppleSDGothicNeo.ttc');
      if (await korean.exists()) {
        final bytes = ByteData.sublistView(await korean.readAsBytes());
        for (final family in ['Roboto', 'Ahem']) {
          final loader = FontLoader(family)..addFont(Future.value(bytes));
          await loader.load();
        }
      }
      final packageConfig = File('.dart_tool/package_config.json');
      final packages =
          jsonDecode(await packageConfig.readAsString())['packages'] as List;
      final flutterPackage = packages.cast<Map<String, dynamic>>().firstWhere(
        (p) => p['name'] == 'flutter',
      );
      final flutterRoot = Directory.fromUri(
        packageConfig.absolute.uri.resolve(flutterPackage['rootUri'] as String),
      ).parent.parent;
      final icons = File(
        '${flutterRoot.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (await icons.exists()) {
        final loader = FontLoader('MaterialIcons');
        loader.addFont(
          Future.value(ByteData.sublistView(await icons.readAsBytes())),
        );
        await loader.load();
      }
    });
    final session = PracticeSession(audio: PreviewAudio());
    await tester.runAsync(session.initialize);
    expect(session.reference, isNotNull);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: VoiceMateApp(startWithProsody: true, prosodySession: session),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      expect(tester.takeException(), isNull);
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final picture = await boundary.toImage(pixelRatio: 2);
        final png = await picture.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory(
          '${Directory.systemTemp.path}/voicemate-integrated-preview',
        );
        await directory.create(recursive: true);
        await File(
          '${directory.path}/$name.png',
        ).writeAsBytes(png!.buffer.asUint8List());
        if (name == '02-native-result-graph') {
          await Directory('../../docs/images').create(recursive: true);
          await File(
            '../../docs/images/prosody-preview.png',
          ).writeAsBytes(png.buffer.asUint8List());
        }
        picture.dispose();
      });
      debugPrint('Captured $name');
    }

    Future<void> scrollTo(Finder finder) async {
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          finder,
          250,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 30,
        );
      }
      final scrolling = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final box = tester.renderObject<RenderBox>(finder);
      final delta = box.localToGlobal(Offset.zero).dy - 94;
      scrolling.jumpTo(
        (scrolling.pixels + delta).clamp(0, scrolling.maxScrollExtent),
      );
      await tester.pumpAndSettle();
    }

    await capture('01-native-ready');
    debugPrint('Preparing native demo');
    await tester.runAsync(session.demo);
    debugPrint('Prepared native demo');
    expect(session.result, isNotNull);
    await tester.pumpAndSettle();
    await scrollTo(find.byType(ProsodyChart));
    await capture('02-native-result-graph');
    await scrollTo(find.text('2. 한 부분씩 이어가 봐요'));
    await capture('03-native-feedback');

    session.phase = PracticePhase.recording;
    session.seconds = .8;
    session.liveTrace = session.result!.analysis.frames
        .where((f) => f.time <= .8)
        .toList();
    session.currentVoice =
        session.liveTrace.isNotEmpty && session.liveTrace.last.active;
    session.liveDomain = session.reference!.analysis.duration * 1.1;
    session.setVolume(false);
    await tester.pumpAndSettle();
    await scrollTo(find.byType(ProsodyChart));
    await capture('04-native-recording');

    session.phase = PracticePhase.idle;
    session.setVolume(false);
    tester.view.physicalSize = const Size(320, 844);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: VoiceMateApp(
          key: const ValueKey('large-text-preview'),
          startWithProsody: true,
          prosodySession: session,
          textScaler: TextScaler.linear(1.5),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scrolling = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    scrolling.jumpTo(0);
    await tester.pumpAndSettle();
    await capture('05-320-large-text-top');
    await scrollTo(find.byType(ProsodyChart));
    await capture('06-320-large-text-graph');
    await scrollTo(find.text('2. 한 부분씩 이어가 봐요'));
    await capture('07-320-large-text-feedback');
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
