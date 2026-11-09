import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:voicemate/features/prosody/audio/audio_analysis.dart';
import 'package:voicemate/features/prosody/audio/wav.dart';

const rate = 16000;

Float64List voice({
  double seconds = 1.6,
  double register = 1,
  double gain = .2,
  bool waiting = false,
  bool internalPause = false,
}) {
  final samples = Float64List((seconds * rate).round());
  var phase = 0.0;
  for (var i = 0; i < samples.length; i++) {
    final time = i / rate;
    final frequency = register * (195 + 30 * math.sin(time * 4));
    phase += 2 * math.pi * frequency / rate;
    if (waiting && (time < .2 || time > seconds - .2)) continue;
    if (internalPause && time > .7 && time < .95) continue;
    samples[i] = gain * math.sin(phase);
  }
  return samples;
}

void main() {
  test(
    'VAD masks pitch evidence without shortening audio or removing internal pauses',
    () {
      final samples = voice(seconds: 1);
      final original = List<double>.of(samples);
      final noSpeech = analyzeSamples(
        samples,
        rate,
        speechFrames: List<int>.filled(100, 0),
      );
      expect(noSpeech.pitchMedian, isNull);
      expect(noSpeech.voicedFrames, 0);
      expect(noSpeech.duration, 1);
      final decisions = List<int>.generate(
        100,
        (index) => index >= 35 && index < 65 ? 0 : 2,
      );
      final mixed = analyzeSamples(samples, rate, speechFrames: decisions);
      expect(mixed.pitchMedian, isNotNull);
      expect(
        mixed.frames
            .where((frame) => frame.time > .4 && frame.time < .6)
            .every((frame) => !frame.active),
        isTrue,
      );
      expect(mixed.duration, 1);
      expect(samples, original);
    },
  );
  test('YIN detects a known live tone while silence remains unmeasured', () {
    final tone = Float64List.fromList(
      List.generate(800, (i) => .2 * math.sin(2 * math.pi * 220 * i / rate)),
    );
    final frame = analyzeFrame(tone, rate);
    expect(frame.active, isTrue);
    expect(frame.pitchHz, closeTo(220, 2));
    expect(analyzeFrame(Float64List(800), rate).pitchHz, isNull);
    expect(analyzeFrame(Float64List(800), rate).active, isFalse);
  });

  test('relative contours ignore whole-register and gain shifts', () {
    final reference = trimAnalysis(analyzeSamples(voice(), rate));
    final shifted = trimAnalysis(
      analyzeSamples(voice(register: 1.2, gain: .08), rate),
    );
    expect(reference.pitchMedian, isNotNull);
    expect(shifted.pitchMedian! / reference.pitchMedian!, closeTo(1.2, .01));
    final compared = compareAnalyses(reference, shifted);
    expect(compared.path, isNotEmpty);
    expect(compared.pitchError!, lessThan(.15));
    expect(compared.intensityError!, lessThan(.15));
  });

  test(
    'self comparison is exactly zero and returns original playback positions',
    () {
      final reference = trimAnalysis(
        analyzeSamples(voice(waiting: true), rate),
      );
      final comparison = compareAnalyses(reference, reference);
      final summary = summarizeComparison(reference, reference, comparison);
      expect(comparison.pitchError, 0);
      expect(comparison.intensityError, 0);
      expect(summary.pitchReliable, isTrue);
      expect(summary.segments.map((s) => s.label), ['앞부분', '중간', '끝부분']);
      expect(reference.startTime, greaterThan(.1));
      for (final segment in summary.segments) {
        expect(segment.userStart, greaterThanOrEqualTo(0));
        expect(segment.userEnd, lessThanOrEqualTo(reference.duration));
        expect(segment.pitchError, anyOf(isNull, 0));
      }
      final trace = alignedTrace(reference, reference, comparison.path);
      expect(trace.length, reference.frames.length);
      for (var i = 0; i < trace.length; i++) {
        expect(trace[i].time, reference.frames[i].time);
        if (!reference.frames[i].active) expect(trace[i].relativePitch, isNull);
      }
    },
  );

  test(
    'internal silence stays a gap and cannot be converted into a voice judgement',
    () {
      final withPause = trimAnalysis(
        analyzeSamples(voice(waiting: true, internalPause: true), rate),
      );
      expect(
        withPause.frames.any((f) => !f.active && f.relativePitch == null),
        isTrue,
      );
      expect(withPause.voicedDuration, lessThan(withPause.duration));
      expect(withPause.recordingDuration, 1.6);
      final silence = analyzeSamples(Float64List(rate), rate);
      final compared = compareAnalyses(withPause, silence);
      expect(compared.path, isEmpty);
      expect(compared.pitchError, isNull);
      expect(compared.intensityError, isNull);
    },
  );

  test('aligned user trace preserves a pause absent from the guide', () {
    final guide = trimAnalysis(analyzeSamples(voice(), rate));
    final user = trimAnalysis(analyzeSamples(voice(internalPause: true), rate));
    final compared = compareAnalyses(guide, user);
    expect(compared.path, isNotEmpty);
    expect(user.frames.any((f) => !f.active), isTrue);
    final trace = alignedTrace(guide, user, compared.path);
    final first = trace.indexWhere((f) => f.relativePitch != null);
    final last = trace.lastIndexWhere((f) => f.relativePitch != null);
    expect(
      trace.sublist(first + 1, last).any((f) => f.relativePitch == null),
      isTrue,
    );
  });

  test(
    'repeated DTW matches cannot create enough independent segment evidence',
    () {
      final a = trimAnalysis(analyzeSamples(voice(), rate));
      final ri = a.frames.indexWhere((f) => f.active);
      final unreliable = Comparison(
        path: List.filled(100, (ri, ri)),
        voicedPairs: 100,
      );
      final summary = summarizeComparison(a, a, unreliable);
      expect(summary.pitchReliable, isFalse);
      expect(summary.segments.every((s) => s.pitchError == null), isTrue);
    },
  );

  test(
    'a cropped reference is recentered and retains its offset in the source audio',
    () {
      final original = trimAnalysis(
        analyzeSamples(voice(seconds: 2, waiting: true), rate),
      );
      final crop = cropReferenceAnalysis(original, start: .4, end: 1.1);
      expect(crop.startTime, closeTo(original.startTime + .4, 1e-9));
      expect(crop.duration, closeTo(.7, 1e-9));
      expect(median(crop.frames.map((f) => f.relativePitch)), closeTo(0, .001));
      expect(median(crop.frames.map((f) => f.relativeDb)), closeTo(0, .001));
      final compared = compareAnalyses(crop, crop);
      expect(compared.pitchError, 0);
      final whole = summarizeComparison(crop, crop, compared, whole: true);
      expect(whole.segments.length, 1);
      expect(whole.segments.single.label, '선택 구간 전체');
      expect(original.duration, greaterThan(crop.duration));
      expect(
        () => cropReferenceAnalysis(original, start: -.1, end: .5),
        throwsArgumentError,
      );
      expect(
        () => cropReferenceAnalysis(original, start: .1, end: .12),
        throwsStateError,
      );
    },
  );

  test('WAV/PCM16 round trips measured samples with explicit sample rate', () {
    final source = voice(seconds: .5);
    final bytes = encodeWav(source, rate);
    final decoded = decodeWav(bytes);
    expect(decoded.sampleRate, rate);
    expect(decoded.samples.length, source.length);
    for (var i = 0; i < source.length; i += 97) {
      expect(decoded.samples[i], closeTo(source[i], 2 / 32768));
    }
    final raw = decodePcm16(Uint8List.sublistView(bytes, 44));
    expect(raw, decoded.samples);
    expect(() => decodePcm16(Uint8List(3)), throwsFormatException);
    expect(() => decodeWav(Uint8List(5)), throwsFormatException);
    expect(
      () => decodeWav(Uint8List.sublistView(bytes, 0, bytes.length - 2)),
      throwsFormatException,
    );
    expect(
      () => analyzeSamples(Float64List(31 * rate), rate),
      throwsRangeError,
    );
  });

  test(
    'IEEE float WAV is decoded rather than treated as 16-bit integer audio',
    () {
      final bytes = Uint8List(44 + 4 * 4), data = ByteData.sublistView(bytes);
      void tag(int at, String value) {
        for (var i = 0; i < value.length; i++) {
          bytes[at + i] = value.codeUnitAt(i);
        }
      }

      tag(0, 'RIFF');
      data.setUint32(4, bytes.length - 8, Endian.little);
      tag(8, 'WAVE');
      tag(12, 'fmt ');
      data.setUint32(16, 16, Endian.little);
      data.setUint16(20, 3, Endian.little);
      data.setUint16(22, 1, Endian.little);
      data.setUint32(24, rate, Endian.little);
      data.setUint32(28, rate * 4, Endian.little);
      data.setUint16(32, 4, Endian.little);
      data.setUint16(34, 32, Endian.little);
      tag(36, 'data');
      data.setUint32(40, 16, Endian.little);
      for (var i = 0; i < 4; i++) {
        data.setFloat32(
          44 + i * 4,
          [-.5, 0, .25, .75][i].toDouble(),
          Endian.little,
        );
      }
      expect(decodeWav(bytes).samples, [-.5, 0, .25, .75]);
    },
  );
}
