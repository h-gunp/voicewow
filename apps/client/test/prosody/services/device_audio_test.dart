import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:voicemate/features/prosody/services/device_audio.dart';

void main() {
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
