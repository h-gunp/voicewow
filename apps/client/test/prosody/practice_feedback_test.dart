import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:voicemate/features/prosody/audio/audio_analysis.dart';
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
    expect(feedback.detail, contains('중간 흐름 전체를 뜻하지'));
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
      expect(feedback.detail, contains('실제 소음계 데시벨이 아니'));
    },
  );
}
