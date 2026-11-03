import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/features/prosody/audio/audio_analysis.dart';
import 'package:voicemate/features/prosody/audio/wav.dart';
import 'package:voicemate/features/prosody/practice_session.dart';
import 'package:voicemate/features/prosody/services/device_audio.dart';

class FakeAudio extends DeviceAudioService {
  void Function(List<double>)? receive;
  bool denied = false;
  int recordingStops = 0;
  void Function()? reachedLimit;
  List<double> samples = List.generate(
    16000,
    (i) => .2 * math.sin(2 * math.pi * 220 * i / 16000),
  );
  @override
  Stream<String> get errors => const Stream.empty();
  @override
  Future<String> storeAudio(
    Uint8List bytes, {
    String name = 'audio.wav',
  }) async => '$name.wav';
  @override
  Future<void> start({
    required void Function(List<double>) onSamples,
    void Function()? onLimitReached,
    void Function(String)? onError,
  }) async {
    if (denied) throw const DeviceAudioException('마이크 권한을 확인해 주세요.');
    receive = onSamples;
    reachedLimit = onLimitReached;
  }

  @override
  Future<RecordedAudio> stop() async {
    recordingStops++;
    return RecordedAudio(
      samples: samples,
      sampleRate: 16000,
      path: 'recording.wav',
      bytes: encodeWav(samples, 16000),
    );
  }

  @override
  Future<GeneratedGuide> generateGuide(String text) async =>
      GeneratedGuide(path: 'invalid.wav', bytes: Uint8List(3));
  @override
  Future<void> stopPlayback() async {}
  @override
  Future<void> cancel() async {}
  @override
  Future<void> cancelGuide() async {}
}

class DeferredCancellationAudio extends FakeAudio {
  final firstCancellation = Completer<void>();
  int guideCancellations = 0, recordingCancellations = 0;
  @override
  Future<void> cancelGuide() async {
    guideCancellations++;
    if (guideCancellations == 1) await firstCancellation.future;
  }

  @override
  Future<void> cancel() async => recordingCancellations++;
}

class DeferredPresetAudio extends FakeAudio {
  final storing = Completer<void>();
  final release = Completer<String>();
  bool delayed = false;
  @override
  Future<String> storeAudio(
    Uint8List bytes, {
    String name = 'audio.wav',
  }) async {
    if (!delayed) {
      delayed = true;
      storing.complete();
      return release.future;
    }
    return '$name.wav';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Dart script preparation preserves phrases and handles decimals and limits',
    () {
      expect(splitPracticeScript('안녕하세요.\n잠시 말씀드릴게요!'), [
        '안녕하세요.',
        '잠시 말씀드릴게요!',
      ]);
      expect(splitPracticeScript('3.14를 읽어요.'), ['3.14를 읽어요.']);
      expect(() => splitPracticeScript(''), throwsFormatException);
      expect(() => splitPracticeScript('가' * 2001), throwsFormatException);
    },
  );
  test(
    'native retries keep a usable result on permissions, silence or guide failure',
    () async {
      final audio = FakeAudio();
      final active = PracticeSession(audio: audio);
      active.reference = ReferenceClip(
        '안녕하세요.',
        'guide.wav',
        trimAnalysis(analyzeSamples(audio.samples, 16000)),
        '시험용',
      );
      await active.startRecording();
      expect(active.recording, isTrue);
      audio.receive!(audio.samples);
      expect(
        active.liveTrace.where((f) => f.relativePitch != null),
        isNotEmpty,
      );
      await active.stopRecording();
      final accepted = active.result, guide = active.reference;
      expect(accepted, isNotNull);
      expect(accepted!.summary.segmentationNote, isNotEmpty);
      audio.denied = true;
      await active.startRecording();
      expect(identical(active.result, accepted), isTrue);
      expect(active.busy, isFalse);
      audio.denied = false;
      audio.samples = List.filled(16000, 0.0);
      await active.startRecording();
      await active.stopRecording();
      expect(identical(active.result, accepted), isTrue);
      await active.generateGuide();
      expect(identical(active.reference, guide), isTrue);
      expect(identical(active.result, accepted), isTrue);
      active.dispose();
    },
  );
  test('an older cancellation cannot stop a newer recording', () async {
    final audio = DeferredCancellationAudio();
    final session = PracticeSession(audio: audio);
    session.reference = ReferenceClip(
      '안녕하세요.',
      'guide.wav',
      trimAnalysis(analyzeSamples(audio.samples, 16000)),
      '시험용',
    );
    await session.startRecording();
    final older = session.cancelCurrent(message: '첫 중단');
    await session.cancelCurrent(message: '최근 중단');
    await session.startRecording();
    final cancelledBeforeRelease = audio.recordingCancellations;
    audio.firstCancellation.complete();
    await older;
    expect(session.recording, isTrue);
    expect(audio.recordingCancellations, cancelledBeforeRelease);
    expect(session.status, isNot(contains('첫 중단')));
    session.dispose();
  });
  test(
    'cancelled preset loading cannot overwrite a newer script or state',
    () async {
      final audio = DeferredPresetAudio();
      final session = PracticeSession(audio: audio);
      final loading = session.initialize();
      await audio.storing.future;
      await session.cancelCurrent();
      session.applyScript('제가 읽고 싶은 문장입니다.');
      final status = session.status;
      audio.release.complete('old-guide.wav');
      await loading;
      expect(session.usingScript, isTrue);
      expect(session.reference, isNull);
      expect(session.phase, PracticePhase.idle);
      expect(session.status, status);
      await session.initialize();
      expect(session.usingScript, isTrue);
      expect(session.reference, isNull);
      session.setMode(false);
      expect(session.reference, isNotNull);
      session.dispose();
    },
  );

  test(
    'an auto-stop cannot accept a take while cancellation is waiting',
    () async {
      final audio = DeferredCancellationAudio();
      final session = PracticeSession(audio: audio);
      session.reference = ReferenceClip(
        '안녕하세요.',
        'guide.wav',
        trimAnalysis(analyzeSamples(audio.samples, 16000)),
        '시험용',
      );
      await session.startRecording();
      final cancelling = session.cancelCurrent();
      expect(session.phase, PracticePhase.cancelling);
      expect(session.recording, isFalse);
      audio.reachedLimit!();
      await session.stopRecording();
      expect(audio.recordingStops, 0);
      expect(session.result, isNull);
      audio.firstCancellation.complete();
      await cancelling;
      expect(session.phase, PracticePhase.idle);
      session.dispose();
    },
  );
}
