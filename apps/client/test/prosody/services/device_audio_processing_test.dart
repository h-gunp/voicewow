import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:voicemate/features/pronunciation/data/pronunciation_recorder_native.dart';
import 'package:voicemate/features/prosody/audio/wav.dart';
import 'package:voicemate/features/prosody/services/device_audio.dart';
import 'package:voicemate/features/prosody/services/practice_audio_processor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('voicemate/practice_audio');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late RecordPlatform previous;
  late _Capture capture;
  late _Processor processor;
  late DeviceAudioService service;
  late Directory directory;

  setUp(() async {
    previous = RecordPlatform.instance;
    capture = _Capture();
    RecordPlatform.instance = capture;
    processor = _Processor();
    messenger.setMockMethodCallHandler(channel, processor.handle);
    directory = await Directory.systemTemp.createTemp('practice_clean_audio_');
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
    service = DeviceAudioService();
  });
  tearDown(() async {
    if (processor.release != null && !processor.release!.isCompleted)
      processor.release!.complete();
    await service.dispose();
    RecordPlatform.instance = previous;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(paths, null);
    await directory.delete(recursive: true);
  });

  test(
    'stop drains capture and native work before saving exactly the live clean PCM',
    () async {
      final live = <double>[];
      processor.release = Completer<void>();
      await service.start(onSamples: live.addAll);
      expect(processor.noiseReductionSelections, [true]);
      expect(processor.voiceActivitySelections, [true]);
      expect(capture.config!.sampleRate, 48000);
      expect(
        capture.config!.androidConfig.audioSource,
        AndroidAudioSource.voiceRecognition,
      );
      expect(capture.config!.autoGain, isFalse);
      expect(capture.config!.echoCancel, isFalse);
      expect(capture.config!.noiseSuppress, isFalse);
      capture.emit(480);
      await processor.started.future;
      capture.tailSamples = 480;
      var completed = false;
      final stopping = service.stop().then((value) {
        completed = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      processor.release!.complete();
      processor.release = null;
      final result = await stopping;
      expect(result.samples, List<double>.filled(320, .125));
      expect(live, result.samples);
      expect(result.sampleRate, 16000);
      expect(result.speechFrames, [1, 1]);
      expect(service.recentVoiceActivity, 'speech');
      expect(
        await File(result.path).readAsBytes(),
        encodeWav(result.samples, 16000),
      );
      expect(processor.methods.where((name) => name == 'finish').length, 1);
    },
  );

  test(
    'pronunciation alone disables suppression and VAD while retaining PCM',
    () async {
      const pronunciation = MethodChannel('voicemate/pronunciation');
      Float32List? recognized;
      messenger.setMockMethodCallHandler(pronunciation, (call) async {
        if (call.method == 'recognize') {
          recognized = (call.arguments as Map)['samples'] as Float32List;
          return ['a'];
        }
        return null;
      });
      final recorder = NativePronunciationRecorder();
      addTearDown(() async {
        await recorder.dispose();
        messenger.setMockMethodCallHandler(pronunciation, null);
      });
      final activities = <String>[];
      await recorder.prepare();
      await recorder.start(
        onLimit: () {},
        onError: (_) {},
        onVoiceActivity: activities.add,
      );
      expect(processor.noiseReductionSelections, [false]);
      expect(processor.voiceActivitySelections, [false]);
      capture.emit(9600);
      await Future<void>.delayed(Duration.zero);
      expect(activities, isEmpty);
      expect(await recorder.finish(), ['A']);
      expect(recognized, Float32List.fromList(List<double>.filled(3200, .125)));
      expect(processor.flags, 0);
      expect(capture.config!.autoGain, isFalse);
      expect(capture.config!.echoCancel, isFalse);
      expect(capture.config!.noiseSuppress, isFalse);
    },
  );

  test(
    'VAD non-speech alone never removes a weak consonant recording',
    () async {
      processor.decision = 0;
      processor.variance = 1e-5;
      await service.start(onSamples: (_) {});
      capture.emit(480);
      final result = await service.stop();
      expect(result.samples.length, 160);
      expect(result.speechFrames, [0]);
      expect(service.recentVoiceActivity, 'nonSpeech');
    },
  );

  test('VAD-off recording has nullable activity and keeps live PCM', () async {
    await service.dispose();
    service = DeviceAudioService(
      noiseReductionEnabled: false,
      voiceActivityEnabled: false,
    );
    processor.variance = 1e-5;
    final live = <double>[];
    await service.start(onSamples: live.addAll);
    capture.emit(480);
    await processor.started.future;
    await Future<void>.delayed(Duration.zero);
    expect(live, List<double>.filled(150, .125));
    expect(service.recentVoiceActivity, isNull);
    final recording = await service.stop();
    expect(recording.samples, List<double>.filled(160, .125));
    expect(live, recording.samples);
    expect(recording.speechFrames, isNull);
    expect(service.speechInRange(0, 160), isNull);
  });

  test('VAD-off recording rejects negligible raw variance', () async {
    await service.dispose();
    service = DeviceAudioService(
      noiseReductionEnabled: false,
      voiceActivityEnabled: false,
    );
    processor.variance = 0;
    await service.start(onSamples: (_) {});
    capture.emit(480);
    await expectLater(service.stop(), throwsA(isA<DeviceAudioException>()));
    expect(processor.flags, 0);
    expect(directory.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test(
    'VAD-off native responses reject decisions and incomplete PCM',
    () async {
      final unexpected = NativePracticeAudioSession();
      await unexpected.create(voiceActivityEnabled: false);
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'process') return null;
        return {
          'samples': Float32List(150),
          'speech': Int32List.fromList([1]),
          'inputSamples': 480,
          'outputSamples': 150,
          'rawVariance': .01,
        };
      });
      await expectLater(unexpected.process(Uint8List(960)), throwsStateError);
      await unexpected.cancel();

      messenger.setMockMethodCallHandler(channel, processor.handle);
      final incomplete = NativePracticeAudioSession();
      await incomplete.create(
        noiseReductionEnabled: false,
        voiceActivityEnabled: false,
      );
      await incomplete.process(Uint8List(960));
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'finish') return null;
        return {
          'samples': Float32List(0),
          'speech': Int32List(0),
          'inputSamples': 480,
          'outputSamples': 150,
          'rawVariance': .01,
        };
      });
      await expectLater(incomplete.finish(), throwsStateError);
      await incomplete.cancel();
    },
  );

  test(
    'local diagnostics are opt-in and keep only accepted current raw bytes',
    () async {
      const enabled = bool.fromEnvironment('VOICEMATE_LOCAL_AUDIO_DIAGNOSTICS');
      await service.start(onSamples: (_) {});
      final expected = Uint8List.fromList(
        List<int>.generate(1440 * 2, (i) => i.isEven ? 0 : 96),
      );
      for (final chunk in [
        expected.sublist(0, 7),
        expected.sublist(7, 1008),
        expected.sublist(1008),
      ]) {
        capture.stream!.add(Uint8List.fromList(chunk));
      }
      final first = await service.stop();
      expect(first.diagnosticsPcm48, enabled ? expected : isNull);
      await service.start(onSamples: (_) {});
      capture.emit(960);
      await service.cancel();
      await service.start(onSamples: (_) {});
      capture.emit(480);
      final next = await service.stop();
      expect(
        next.diagnosticsPcm48,
        enabled ? expected.sublist(0, 960) : isNull,
      );
    },
  );

  test('native response rejects excess VAD decisions', () async {
    final session = NativePracticeAudioSession();
    await session.create();
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'process'
          ? {
              'samples': Float32List(0),
              'speech': Int32List.fromList([1, 1]),
              'inputSamples': 480,
              'outputSamples': 0,
              'rawVariance': .01,
            }
          : null,
    );
    await expectLater(session.process(Uint8List(960)), throwsStateError);
    await session.cancel();
  });

  test('unresponsive native processing has a bounded deadline', () async {
    final session = NativePracticeAudioSession();
    await session.create();
    messenger.setMockMethodCallHandler(
      channel,
      (call) => call.method == 'process'
          ? Completer<Object?>().future
          : Future<Object?>.value(null),
    );
    await expectLater(
      session.process(Uint8List(960)),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'audio_processing_timeout',
        ),
      ),
    );
    await session.cancel();
  });

  test(
    'confirmed non-speech plus negligible raw variance rejects empty audio',
    () async {
      processor.decision = 0;
      processor.variance = 0;
      await service.start(onSamples: (_) {});
      capture.emit(480);
      await expectLater(
        service.stop(),
        throwsA(
          isA<DeviceAudioException>().having(
            (error) => error.message,
            'message',
            contains('목소리를 찾지 못했어요'),
          ),
        ),
      );
      expect(directory.listSync(recursive: true).whereType<File>(), isEmpty);
    },
  );

  test(
    'cancel discards delayed processed audio and drains before a fresh session',
    () async {
      final live = <double>[];
      processor.release = Completer<void>();
      await service.start(onSamples: live.addAll);
      capture.emit(960);
      await processor.started.future;
      final cancelling = service.cancel();
      await expectLater(
        service.start(onSamples: (_) {}),
        throwsA(isA<DeviceAudioException>()),
      );
      processor.release!.complete();
      processor.release = null;
      await cancelling;
      expect(live, isEmpty);
      await service.start(onSamples: live.addAll);
      capture.emit(480);
      final result = await service.stop();
      expect(result.samples.length, 160);
      expect(live, result.samples);
      expect(processor.createdIds.toSet().length, 2);
    },
  );
}

class _Capture extends RecordPlatform {
  StreamController<Uint8List>? stream;
  RecordConfig? config;
  int tailSamples = 0;
  void emit(int samples) => stream!.add(
    Uint8List.fromList(
      List<int>.generate(samples * 2, (i) => i.isEven ? 0 : 96),
    ),
  );
  @override
  Future<void> create(String recorderId) async {}
  @override
  Stream<RecordState> onStateChanged(String recorderId) => const Stream.empty();
  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      true;
  @override
  Future<bool> isEncoderSupported(
    String recorderId,
    AudioEncoder encoder,
  ) async => true;
  @override
  void setOnConfigChanged(
    String recorderId,
    void Function(RecordConfig)? handler,
  ) {}
  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig value,
  ) async {
    config = value;
    stream = StreamController<Uint8List>();
    return stream!.stream;
  }

  @override
  Future<String?> stop(String recorderId) async {
    if (tailSamples > 0) emit(tailSamples);
    await stream?.close();
    return null;
  }

  @override
  Future<void> cancel(String recorderId) async {
    await stream?.close();
  }

  @override
  Future<void> dispose(String recorderId) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Processor {
  final methods = <String>[], createdIds = <int>[];
  final noiseReductionSelections = <bool?>[];
  final voiceActivitySelections = <bool?>[];
  bool noiseReductionEnabled = true;
  bool voiceActivityEnabled = true;
  final started = Completer<void>();
  Completer<void>? release;
  int input = 0, output = 0, flags = 0, decision = 1, capturedBytes = 0;
  double variance = .01;
  Future<Object?> handle(MethodCall call) async {
    methods.add(call.method);
    final args = call.arguments as Map;
    if (call.method == 'create') {
      createdIds.add(args['session'] as int);
      noiseReductionSelections.add(args['noiseReductionEnabled'] as bool?);
      noiseReductionEnabled = args['noiseReductionEnabled'] as bool? ?? true;
      voiceActivitySelections.add(args['voiceActivityEnabled'] as bool?);
      voiceActivityEnabled = args['voiceActivityEnabled'] as bool? ?? true;
      input = output = flags = capturedBytes = 0;
      return {'inputSampleRate': 48000, 'sampleRate': 16000};
    }
    if (call.method == 'cancel') return null;
    if (call.method == 'process') {
      if (!started.isCompleted) started.complete();
      await release?.future;
      capturedBytes += (args['pcm'] as Uint8List).length;
      input = capturedBytes ~/ 2;
    }
    final finished = call.method == 'finish';
    final readyFrames = finished
        ? (input + 479) ~/ 480
        : (input ~/ 480 - (noiseReductionEnabled ? 1 : 0)).clamp(0, 2000);
    final nextOutput = finished
        ? (input + 2) ~/ 3
        : (readyFrames * 160 - (noiseReductionEnabled ? 0 : 10)).clamp(
            0,
            320000,
          );
    final samples = Float32List.fromList(
      List<double>.filled(nextOutput - output, .125),
    );
    final speech = Int32List.fromList(
      List<int>.filled(
        voiceActivityEnabled ? readyFrames - flags : 0,
        decision,
      ),
    );
    output = nextOutput;
    flags = voiceActivityEnabled ? readyFrames : 0;
    return {
      'samples': samples,
      'speech': speech,
      'inputSamples': input,
      'outputSamples': output,
      'rawVariance': variance,
    };
  }
}
