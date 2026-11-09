import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/features/pronunciation/data/pronunciation_recorder_native.dart';
import 'package:voicemate/features/prosody/services/device_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('voicemate/pronunciation');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall) platform;

  Future<void> progress(MethodCall source, String message) async {
    final args = source.arguments as Map;
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('progress', {
          'session': args['session'],
          'request': args['request'],
          'message': message,
        }),
      ),
      (_) {},
    );
  }

  setUp(() {
    calls = [];
    platform = (call) async => call.method == 'recognize' ? ['ɡ', 'a'] : null;
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return platform(call);
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'desktop factory stays unavailable without touching a platform channel',
    () async {
      if (Platform.isAndroid) return;
      final recorder = createPronunciationRecorder();
      expect(recorder, isNot(isA<NativePronunciationRecorder>()));
      await expectLater(recorder.prepare(), throwsStateError);
      await recorder.cancel();
      await recorder.dispose();
      expect(calls, isEmpty);
    },
  );

  test('a new recording waits for cancelled native startup to drain', () async {
    final audio = _Audio()..starting = Completer<void>();
    final recorder = NativePronunciationRecorder(audio: audio);
    await recorder.prepare();
    final oldStart = recorder.start(onLimit: () {}, onError: (_) {});
    final oldCancelled = expectLater(oldStart, throwsA(anything));
    await Future<void>.delayed(Duration.zero);
    await recorder.cancel();
    await recorder.prepare();
    final newStart = recorder.start(onLimit: () {}, onError: (_) {});
    await Future<void>.delayed(Duration.zero);
    final startsBeforeDrain = audio.starts;
    audio.starting!.complete();
    await oldCancelled;
    await newStart;
    expect(startsBeforeDrain, 1);
    expect(audio.starts, 2);
    await recorder.dispose();
  });

  test('finish passes final PCM only and keeps local replay', () async {
    final audio = _Audio();
    final recorder = NativePronunciationRecorder(audio: audio);
    await recorder.prepare();
    await recorder.start(onLimit: () {}, onError: (_) {});
    expect(await recorder.finish(), ['G', 'A']);
    final args =
        calls.singleWhere((c) => c.method == 'recognize').arguments as Map;
    expect(args.keys.toSet(), {'session', 'request', 'samples', 'sampleRate'});
    expect(args['samples'], isA<Float32List>());
    expect((args['samples'] as Float32List).last, 0.75);
    expect(args['sampleRate'], 16000);
    await recorder.play();
    expect(audio.played, 'memory.wav');
    await recorder.dispose();
    expect(audio.disposed, isTrue);
  });

  test('voice activity deduplicates states and drops stale samples', () async {
    final audio = _Audio();
    final recorder = NativePronunciationRecorder(audio: audio);
    final activities = <String>[];
    await recorder.prepare();
    await recorder.start(
      onLimit: () {},
      onError: (_) {},
      onVoiceActivity: activities.add,
    );
    final oldSamples = audio.samplesCallback!;
    for (final activity in [
      null,
      'nonSpeech',
      'nonSpeech',
      'speech',
      'uncertain',
      'invalid',
    ]) {
      audio.activity = activity;
      oldSamples([0.1]);
    }
    expect(activities, ['nonSpeech', 'speech', 'uncertain']);
    expect(await recorder.finish(), ['G', 'A']);
    audio.activity = 'speech';
    oldSamples([0.1]);
    expect(activities, hasLength(3));
    await recorder.start(
      onLimit: () {},
      onError: (_) {},
      onVoiceActivity: activities.add,
    );
    oldSamples([0.1]);
    expect(activities, hasLength(3));
    audio.samplesCallback!([0.1]);
    expect(activities, ['nonSpeech', 'speech', 'uncertain', 'speech']);
    final latestSamples = audio.samplesCallback!;
    await recorder.cancel();
    audio.activity = 'nonSpeech';
    latestSamples([0.1]);
    expect(activities, hasLength(4));
    await recorder.dispose();
    latestSamples([0.1]);
    expect(activities, hasLength(4));
  });

  test('replay waits for completion and rejects a second operation', () async {
    final audio = _Audio()..playback = Completer<void>();
    final recorder = NativePronunciationRecorder(audio: audio);
    await recorder.prepare();
    await recorder.start(onLimit: () {}, onError: (_) {});
    await recorder.finish();
    var completed = false;
    final playing = recorder.play().then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    await expectLater(
      recorder.start(onLimit: () {}, onError: (_) {}),
      throwsA(anything),
    );
    audio.playback!.complete();
    await playing;
    await recorder.dispose();
  });

  test(
    'cancelled preparation drops progress and cannot start recording',
    () async {
      final done = Completer<Object?>();
      platform = (call) =>
          call.method == 'prepare' ? done.future : Future.value(null);
      final audio = _Audio();
      final recorder = NativePronunciationRecorder(audio: audio);
      final messages = <String>[];
      final preparing = recorder.prepare(onProgress: messages.add);
      final cancelled = expectLater(preparing, throwsA(anything));
      await Future<void>.delayed(Duration.zero);
      final source = calls.singleWhere((c) => c.method == 'prepare');
      await recorder.cancel();
      await progress(source, 'late download');
      done.complete();
      await cancelled;
      expect(messages, isEmpty);
      await expectLater(
        recorder.start(onLimit: () {}, onError: (_) {}),
        throwsA(anything),
      );
      expect(audio.starts, 0);
      await recorder.dispose();
    },
  );

  test('late inference cannot replace a cancelled recording', () async {
    final inference = Completer<Object?>();
    platform = (call) =>
        call.method == 'recognize' ? inference.future : Future.value(null);
    final audio = _Audio();
    final recorder = NativePronunciationRecorder(audio: audio);
    await recorder.prepare();
    await recorder.start(onLimit: () {}, onError: (_) {});
    final finishing = recorder.finish();
    final cancelled = expectLater(finishing, throwsA(anything));
    await Future<void>.delayed(Duration.zero);
    await recorder.cancel();
    inference.complete(['G', 'A']);
    await cancelled;
    await expectLater(recorder.play(), throwsA(anything));
    expect(audio.played, isNull);
    await recorder.dispose();
  });

  test(
    'disposing an older recorder leaves new progress listener alive',
    () async {
      final first = NativePronunciationRecorder(audio: _Audio());
      final second = NativePronunciationRecorder(audio: _Audio());
      await first.prepare();
      final done = Completer<Object?>();
      platform = (call) =>
          call.method == 'prepare' ? done.future : Future.value(null);
      final messages = <String>[];
      final preparing = second.prepare(onProgress: messages.add);
      await Future<void>.delayed(Duration.zero);
      final source = calls.lastWhere((c) => c.method == 'prepare');
      await first.dispose();
      await progress(source, 'new session');
      done.complete();
      await preparing;
      expect(messages, ['new session']);
      await second.dispose();
    },
  );
}

class _Audio extends DeviceAudioService {
  int starts = 0;
  String? played;
  bool disposed = false;
  Completer<void>? playback;
  Completer<void>? starting;
  String? activity;
  void Function(List<double>)? samplesCallback;
  @override
  String? get recentVoiceActivity => activity;
  @override
  Future<void> start({
    required void Function(List<double>) onSamples,
    void Function()? onLimitReached,
    void Function(String)? onError,
  }) async {
    starts++;
    samplesCallback = onSamples;
    if (starts == 1) await starting?.future;
    onSamples([0.1]);
  }

  @override
  Future<RecordedAudio> stop() async => RecordedAudio(
    samples: List.generate(
      3200,
      (i) => i == 3199 ? 0.75 : (i.isEven ? 0.1 : -0.1),
    ),
    sampleRate: 16000,
    path: 'memory.wav',
    bytes: Uint8List(0),
  );
  @override
  Future<void> cancel() async {}
  @override
  Future<void> stopPlayback() async {}
  @override
  Future<void> play(
    String path, {
    Duration? start,
    Duration? end,
    bool waitForCompletion = false,
  }) async {
    played = path;
    if (waitForCompletion) await playback?.future;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
