// Manual native UI preview, without microphone or platform audio plugins.
// flutter test tools/preview_prosody.dart
// PNGs: /private/tmp/voicemate-integrated-preview/
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
  testWidgets(
    'capture the separate native preparation, recording and result views',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        // Optional Mac preview font; no font file is bundled with the app.
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
          packageConfig.absolute.uri.resolve(
            flutterPackage['rootUri'] as String,
          ),
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
          picture.dispose();
        });
        debugPrint('Captured $name');
      }

      Future<void> scrollTo(Finder finder) async {
        await tester.scrollUntilVisible(
          finder,
          200,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 30,
        );
        // A second layout resolves variable-height ListView estimates.
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(tester.element(finder), alignment: 0);
        await tester.pumpAndSettle();
      }

      await capture('01-step-prepare');
      await tester.tap(find.byKey(const Key('prosody-prepare-next')));
      await tester.pumpAndSettle();
      expect(session.recording, isFalse);
      await capture('02-step-record-ready');
      session.phase = PracticePhase.recording;
      session.seconds = .8;
      session.liveTrace = session.reference!.analysis.frames
          .where((f) => f.time <= .8)
          .toList();
      session.currentVoice =
          session.liveTrace.isNotEmpty && session.liveTrace.last.active;
      session.liveDomain = session.reference!.analysis.duration * 1.1;
      session.setVolume(false);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('prosody-record-toggle')).hitTestable(),
        findsOneWidget,
      );
      await capture('03-step-record-live');

      session.phase = PracticePhase.idle;
      await tester.runAsync(session.demo);
      expect(session.result, isNotNull);
      await tester.pumpAndSettle();
      await capture('04-step-result-graph');
      await scrollTo(find.text('이번 목소리'));
      await capture('05-step-result-feedback');

      // A narrower phone and doubled body text keep recording controls reachable.
      tester.view.physicalSize = const Size(320, 844);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: VoiceMateApp(
            key: const ValueKey('large-text-preview'),
            startWithProsody: true,
            prosodySession: session,
            textScaler: TextScaler.linear(2),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prosody-back')));
      await tester.pumpAndSettle();
      await capture('06-320-record-ready-large-text');
      session.phase = PracticePhase.recording;
      session.seconds = .8;
      session.setVolume(false);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('prosody-record-toggle')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('prosody-record-cancel')).hitTestable(),
        findsOneWidget,
      );
      await capture('07-320-record-live-large-text');
      await tester.tap(find.byKey(const Key('prosody-record-cancel')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('prosody-previous-result')),
      );
      await tester.tap(find.byKey(const Key('prosody-previous-result')));
      await tester.pumpAndSettle();
      await scrollTo(find.byType(ProsodyChart));
      await capture('08-320-result-graph-large-text');
      await scrollTo(find.text('이번 목소리'));
      await capture('09-320-result-feedback-large-text');
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
