import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:voicemate/features/prosody/audio/audio_analysis.dart';
import 'package:voicemate/features/prosody/audio/wav.dart';
import 'package:voicemate/features/prosody/practice_feedback.dart';

AudioAnalysis curve(
  double Function(double) pitch, {
  double Function(double)? level,
}) => AudioAnalysis(
  duration: 1.2,
  frames: List.generate(61, (i) {
    final t = i * .02, p = pitch(i * .02), db = level?.call(i * .02) ?? 0.0;
    return AudioFrame(
      time: t,
      pitchHz: (180 * math.pow(2, p / 12)).toDouble(),
      rmsDb: -20 + db,
      active: true,
      relativePitch: p,
      relativeDb: db,
    );
  }),
);

const segment = Segment(
  label: '전체',
  start: 0,
  end: 1.2,
  userStart: 0,
  userEnd: 1.2,
  pairs: 61,
);
Comparison direct() =>
    Comparison(path: List.generate(61, (i) => (i, i)), voicedPairs: 61);

AudioAnalysis realGuide(String name) {
  final wav = decodeWav(
    File('assets/prosody/guides/$name.wav').readAsBytesSync(),
  );
  return trimAnalysis(analyzeSamples(wav.samples, wav.sampleRate));
}

List<(String, double, double)> boundaries(ComparisonSummary summary) =>
    summary.segments.map((s) => (s.label, s.start, s.end)).toList();

void main() {
  test(
    'matching endpoint direction is encouraged independently of amplitude differences',
    () {
      final reference = curve((t) => t * 6);
      for (final slope in [.3, 2.0, 18.0]) {
        final feedback = practiceFeedback(
          reference,
          curve((t) => t * slope),
          direct(),
          segment,
        );
        expect(feedback.available, isTrue);
        expect(feedback.tone, 'encourage');
        expect(feedback.referenceDelta, isPositive);
        expect(feedback.userDelta, isPositive);
        expect(feedback.observation, isNot(contains('반음')));
        expect(feedback.detail, contains('반음'));
        expect(feedback.action, isNot(contains('듣고')));
      }
    },
  );

  test(
    'opposite direction gets one graph-based practice action without a failure grade',
    () {
      final feedback = practiceFeedback(
        curve((t) => t * 6),
        curve((t) => -t * 6),
        direct(),
        segment,
      );
      expect(feedback.available, isTrue);
      expect(feedback.tone, 'practice');
      expect(feedback.action, contains('파란 선'));
      expect(feedback.action, contains('조금 높여서'));
      expect(feedback.action, isNot(matches(RegExp('듣고|불합격|틀렸|정상'))));
    },
  );

  test(
    'static offsets and repeated matching pairs do not become movement or evidence',
    () {
      final reference = curve((t) => t * 6), user = curve((t) => t * 6 + 8);
      final repeated = Comparison(
        path: [...direct().path, ...List.generate(300, (_) => (1, 1))],
      );
      final ordinary = practiceFeedback(reference, user, direct(), segment);
      final duplicate = practiceFeedback(reference, user, repeated, segment);
      expect(ordinary.tone, 'encourage');
      expect(ordinary.referenceDelta, closeTo(ordinary.userDelta!, 1e-9));
      expect(duplicate.userDelta, ordinary.userDelta);
      final sparse = Comparison(
        path: List.generate(200, (i) => (i % 4, i % 4)),
      );
      final unavailable = practiceFeedback(reference, user, sparse, segment);
      expect(unavailable.available, isFalse);
      expect(unavailable.userDelta, isNull);
      expect(unavailable.tone, 'uncertain');
    },
  );

  test('rounded zero does not certify a flat contour or erase a hump', () {
    final hump = curve((t) => math.sin(t * math.pi / 1.2) * 6);
    final feedback = practiceFeedback(hump, hump, direct(), segment);
    expect(feedback.available, isTrue);
    expect(feedback.tone, 'neutral');
    expect(feedback.observation, isNot(matches(RegExp('평평|일정|정상|성공'))));
    expect(feedback.detail, contains('앞·뒤 구간을 비교'));
  });

  test(
    'relative volume keeps its units in details without claiming sound-pressure calibration',
    () {
      final feedback = practiceFeedback(
        curve((t) => t, level: (t) => t * 9),
        curve((t) => t, level: (t) => -t * 9),
        direct(),
        segment,
        volume: true,
      );
      expect(feedback.tone, 'practice');
      expect(feedback.action, contains('조금 키워서'));
      expect(feedback.detail, contains('dB'));
      expect(feedback.detail, contains('각 녹음의 중간값을 기준으로 한 상대 dB'));
    },
  );

  test(
    'every displayed real guide self-comparison has measured endpoint support',
    () {
      for (final name in ['hello', 'sunglasses', 'phrase']) {
        final reference = realGuide(name);
        final comparison = compareAnalyses(reference, reference);
        final summary = buildPracticeSummary(reference, reference, comparison);
        expect(comparison.pitchError, 0, reason: name);
        expect(summary.segments, isNotEmpty);
        expect(summary.segmentationNote, isNotEmpty);
        for (final segment in summary.segments) {
          for (final volume in [false, true]) {
            final feedback = practiceFeedback(
              reference,
              reference,
              comparison,
              segment,
              volume: volume,
            );
            expect(
              feedback.available,
              isTrue,
              reason: '$name ${segment.label}',
            );
            expect(feedback.referenceDelta, feedback.userDelta);
            expect(feedback.detail, contains('측정 구간'));
          }
        }
      }
    },
  );

  test(
    'short real guide uses reference-only halves instead of an unsupported middle third',
    () {
      final reference = realGuide('hello');
      final comparison = compareAnalyses(reference, reference);
      final summary = buildPracticeSummary(reference, reference, comparison);
      expect(summary.segments.map((s) => s.label), ['앞부분', '뒷부분']);
      expect(summary.segmentationNote, contains('두 구간'));
      final phrase = realGuide('phrase');
      final phraseSummary = buildPracticeSummary(
        phrase,
        phrase,
        compareAnalyses(phrase, phrase),
      );
      expect(phraseSummary.segments, hasLength(3));
      // The previously rejected 100–120ms blanks are still unmeasured.
      expect(phrase.frames.where((f) => !f.active).length, greaterThan(5));
      final trace = alignedTrace(
        phrase,
        phrase,
        compareAnalyses(phrase, phrase).path,
      );
      for (var i = 0; i < trace.length; i++) {
        if (!phrase.frames[i].active) expect(trace[i].relativePitch, isNull);
      }
    },
  );

  test(
    'leading and internal pauses in actual WAV audio stay gaps without suppressing every comparison',
    () {
      final wav = decodeWav(
        File('assets/prosody/guides/phrase.wav').readAsBytesSync(),
      );
      final split = (wav.sampleRate * .9).round();
      final leading = List<double>.filled((wav.sampleRate * .3).round(), 0);
      final pause = List<double>.filled((wav.sampleRate * .25).round(), 0);
      final paused = trimAnalysis(
        analyzeSamples([
          ...leading,
          ...wav.samples.take(split),
          ...pause,
          ...wav.samples.skip(split),
        ], wav.sampleRate),
      );
      final original = realGuide('phrase');
      final comparison = compareAnalyses(original, paused);
      final summary = buildPracticeSummary(original, paused, comparison);
      expect(paused.startTime, greaterThan(.2));
      expect(
        paused.frames.any((f) => !f.active && f.relativePitch == null),
        isTrue,
      );
      expect(
        summary.segments.any(
          (s) => practiceFeedback(original, paused, comparison, s).available,
        ),
        isTrue,
      );
      expect(
        boundaries(summary),
        boundaries(
          buildPracticeSummary(
            original,
            original,
            compareAnalyses(original, original),
          ),
        ),
      );
    },
  );

  test(
    'a genuinely short real clip falls back to whole without lowering evidence requirements',
    () {
      final reference = cropReferenceAnalysis(
        realGuide('sunglasses'),
        start: .65,
        end: .85,
      );
      final comparison = compareAnalyses(reference, reference);
      final summary = buildPracticeSummary(reference, reference, comparison);
      expect(summary.segments, hasLength(1));
      expect(summary.segments.single.label, '전체 흐름');
      expect(
        practiceFeedback(
          reference,
          reference,
          comparison,
          summary.segments.single,
        ).available,
        isTrue,
      );
      final selected = buildPracticeSummary(
        reference,
        reference,
        comparison,
        whole: true,
      );
      expect(selected.segments.single.label, '선택 구간 전체');
      expect(selected.segmentationNote, contains('선택한 구간'));
    },
  );

  test(
    'noise and silence cannot change guide partitions or receive invented feedback',
    () {
      final reference = realGuide('hello');
      final self = buildPracticeSummary(
        reference,
        reference,
        compareAnalyses(reference, reference),
      );
      final random = math.Random(17);
      final noise = Float64List.fromList(
        List.generate(16000, (_) => (random.nextDouble() * 2 - 1) * .06),
      );
      for (final samples in [Float64List(16000), noise]) {
        final user = trimAnalysis(analyzeSamples(samples, 16000));
        final comparison = compareAnalyses(reference, user);
        final summary = buildPracticeSummary(reference, user, comparison);
        expect(user.voicedFrames, 0);
        expect(boundaries(summary), boundaries(self));
        for (final segment in summary.segments) {
          final feedback = practiceFeedback(
            reference,
            user,
            comparison,
            segment,
          );
          expect(feedback.available, isFalse);
          expect(feedback.userDelta, isNull);
          expect(feedback.observation, isNot(matches(RegExp('잘못|실패|정상|비정상'))));
          expect(feedback.action, isNot(contains('마이크 위치')));
        }
      }
    },
  );

  test(
    'separated sparse observations never count as continuous endpoint windows',
    () {
      final reference = curve((t) => t * 6);
      final sparse = AudioAnalysis(
        duration: reference.duration,
        frames: reference.frames
            .asMap()
            .entries
            .map(
              (entry) => entry.key % 5 == 0
                  ? entry.value
                  : entry.value.copyWith(
                      active: false,
                      pitchHz: null,
                      relativePitch: null,
                      relativeDb: null,
                    ),
            )
            .toList(),
      );
      final feedback = practiceFeedback(reference, sparse, direct(), segment);
      expect(feedback.available, isFalse);
      expect(feedback.userDelta, isNull);
    },
  );
}
