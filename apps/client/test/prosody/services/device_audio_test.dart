import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, StandardMethodCodec;
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:voicemate/features/prosody/audio/wav.dart';
import 'package:voicemate/features/prosody/services/device_audio.dart';
import 'package:voicemate/shared/native_tts_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('native synthesis errors', () {
    const ttsChannel = MethodChannel('flutter_tts');
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late Directory directory;
    late DeviceAudioService service;
    late _SynthesisPlatform platform;

    setUp(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      directory = await Directory.systemTemp.createTemp('voicemate_tts_test_');
      service = DeviceAudioService();
      platform = _SynthesisPlatform();
      messenger.setMockMethodCallHandler(ttsChannel, platform.handle);
      messenger.setMockMethodCallHandler(
        pathChannel,
        (_) async => directory.path,
      );
    });

    tearDown(() async {
      await service.cancelGuide();
      await platform.event('speak.onCancel');
      await service.dispose();
      for (final pending in platform.pending) {
        if (!pending.isCompleted) pending.complete(1);
      }
      messenger.setMockMethodCallHandler(ttsChannel, null);
      messenger.setMockMethodCallHandler(pathChannel, null);
      debugDefaultTargetPlatformOverride = null;
      await directory.delete(recursive: true);
    });

    test(
      'synth.onError fails immediately, removes partial output and permits retry',
      () async {
        final generating = service.generateGuide('안녕하세요.');
        final failed = expectLater(
          generating.timeout(const Duration(seconds: 1)),
          throwsA(
            isA<DeviceAudioException>().having(
              (error) => error.message,
              'message',
              contains('기기에서 가이드 음성을 만들지 못했어요'),
            ),
          ),
        );
        await platform.started.future.timeout(const Duration(seconds: 1));
        final partial = File(platform.paths.single);
        expect(await partial.exists(), isTrue);
        await platform.event(
          'synth.onError',
          'Error from TextToSpeech (synth) - 5',
        );
        await failed;
        expect(service.isGenerating, isFalse);
        expect(platform.pending.single.isCompleted, isFalse);
        expect(await partial.exists(), isFalse);

        platform.started = Completer<void>();
        final retry = service.generateGuide('다시 읽는다.');
        await platform.started.future.timeout(const Duration(seconds: 1));
        final bytes = encodeWav(List<double>.filled(160, 0), 16000);
        await File(platform.paths.last).writeAsBytes(bytes);
        platform.pending.last.complete(1);
        await platform.event('synth.onComplete');
        expect((await retry).bytes, bytes);
        expect(service.isGenerating, isFalse);
      },
    );

    test(
      'an error delivered during issue is handled without an unhandled future',
      () async {
        platform.failDuringIssue = true;
        await expectLater(
          service
              .generateGuide('바로 오류가 난다.')
              .timeout(const Duration(seconds: 1)),
          throwsA(
            isA<DeviceAudioException>().having(
              (error) => error.message,
              'message',
              contains('기기에서 가이드 음성을 만들지 못했어요'),
            ),
          ),
        );
        expect(service.isGenerating, isFalse);
        expect(await File(platform.paths.single).exists(), isFalse);
        final next = await NativeTtsCoordinator.shared.acquire(
          NativeTtsKind.speech,
          timeout: Duration.zero,
        );
        expect(next, isNotNull);
        next!.releaseUnissued();
      },
    );
  });

  test('Android TTS string flags select installed offline Korean voices', () {
    expect(
      isInstalledOfflineKoreanVoice({
        'locale': 'ko-KR',
        'network_required': '0',
        'features': '',
      }),
      isTrue,
    );
    for (final flag in [false, 0, 'false']) {
      expect(
        isInstalledOfflineKoreanVoice({
          'locale': 'ko_KR',
          'network_required': flag,
        }),
        isTrue,
      );
    }
    for (final flag in [true, 1, '1', 'true', null]) {
      expect(
        isInstalledOfflineKoreanVoice({
          'locale': 'ko-KR',
          'network_required': flag,
        }),
        isFalse,
      );
    }
    expect(
      isInstalledOfflineKoreanVoice({
        'locale': 'ko-KR',
        'network_required': '0',
        'features': 'notInstalled',
      }),
      isFalse,
    );
    expect(
      isInstalledOfflineKoreanVoice({
        'locale': 'en-US',
        'network_required': '0',
      }),
      isFalse,
    );
  });

  test(
    'cancellation during encoder lookup never opens a microphone later',
    () async {
      final previous = RecordPlatform.instance;
      final fake = _DelayedRecordPlatform();
      RecordPlatform.instance = fake;
      final service = DeviceAudioService();
      try {
        final start = service.start(onSamples: (_) {});
        await fake.lookupStarted.future;
        final cancel = service.cancel();
        fake.encoderAllowed.complete(true);
        await cancel;
        await start;
        expect(fake.startCalls, 0);
        expect(service.isRecording, isFalse);
      } finally {
        await service.dispose();
        RecordPlatform.instance = previous;
      }
    },
  );

  test(
    'PCM16 chunk boundaries preserve signed samples including an odd carry byte',
    () {
      final decoder = Pcm16StreamDecoder();
      expect(decoder.add(Uint8List.fromList([0x00])), isEmpty);
      expect(decoder.add(Uint8List.fromList([0x80, 0xff, 0x7f, 0x00])), [
        -1.0,
        32767 / 32768.0,
      ]);
      expect(decoder.add(Uint8List.fromList([0x00, 0x00, 0x40])), [0.0, 0.5]);
    },
  );

  test(
    'empty chunks retain pending bytes and a new recording discards the carry',
    () {
      final decoder = Pcm16StreamDecoder();
      expect(decoder.add(Uint8List.fromList([0xff])), isEmpty);
      expect(decoder.add(Uint8List(0)), isEmpty);
      expect(decoder.add(Uint8List.fromList([0xff])), [-1 / 32768.0]);
      decoder.add(Uint8List.fromList([0x12]));
      decoder.reset();
      expect(decoder.add(Uint8List.fromList([0x00, 0x20])), [0.25]);
    },
  );

  test(
    'constructing and disposing an unused service needs no plugin or microphone',
    () async {
      final service = DeviceAudioService();
      expect(service.isRecording, false);
      expect(service.isGenerating, false);
      await service.dispose();
      await service.dispose();
    },
  );
}

class _SynthesisPlatform {
  Completer<void> started = Completer<void>();
  final pending = <Completer<Object?>>[];
  final paths = <String>[];
  bool failDuringIssue = false;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'isLanguageInstalled':
        return true;
      case 'getVoices':
        return [
          {
            'locale': 'ko-KR',
            'network_required': '0',
            'features': '',
            'name': 'offline',
          },
        ];
      case 'synthesizeToFile':
        final path = (call.arguments as Map)['fileName'] as String;
        paths.add(path);
        await File(path).writeAsBytes([1, 2, 3]);
        final completion = Completer<Object?>();
        pending.add(completion);
        if (failDuringIssue) await event('synth.onError', 'synthesis failed');
        started.complete();
        // Android reports synth.onError without resolving this method result.
        return completion.future;
      default:
        return 1;
    }
  }

  Future<void> event(String method, [Object? arguments]) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'flutter_tts',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, arguments),
          ),
          null,
        );
  }
}

class _DelayedRecordPlatform extends RecordPlatform {
  final lookupStarted = Completer<void>();
  final encoderAllowed = Completer<bool>();
  var startCalls = 0;
  @override
  Future<void> create(String recorderId) async {}
  @override
  Stream<RecordState> onStateChanged(String recorderId) => const Stream.empty();
  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      true;
  @override
  Future<bool> isEncoderSupported(String recorderId, AudioEncoder encoder) {
    lookupStarted.complete();
    return encoderAllowed.future;
  }

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) async {
    startCalls++;
    return const Stream.empty();
  }

  @override
  void setOnConfigChanged(
    String recorderId,
    void Function(RecordConfig)? handler,
  ) {}
  @override
  Future<void> cancel(String recorderId) async {}
  @override
  Future<void> dispose(String recorderId) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
