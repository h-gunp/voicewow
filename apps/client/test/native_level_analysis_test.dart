import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/audio/native_level_analysis.dart';

Map<String, Object?> frame(
  int seq, {
  double power = .0001,
  String speech = 'nonSpeech',
  bool clipped = false,
  double meterRms = .01,
}) => {
  'seq': seq,
  'power': power,
  'speech': speech,
  'clipped': clipped,
  'meterRms': meterRms,
};

void collect(
  NativeLevelAnalysis analysis, {
  int start = 0,
  int count = 500,
  double power = .0001,
  bool clipped = false,
}) {
  for (var seq = start; seq < start + count; seq++) {
    analysis.add(frame(seq, power: power, clipped: clipped));
  }
}

void main() {
  test('manual sampling uses 500 disjoint frames and raw power', () {
    final analysis = NativeLevelAnalysis();
    collect(analysis, count: 10);
    expect(analysis.snapshot['state'], 'idle');
    expect(analysis.snapshot['calibrationValid'], false);
    analysis.sample();
    collect(analysis, start: 10, count: 499);
    expect(analysis.snapshot['state'], 'collecting');
    expect(analysis.snapshot['progress'], 499 / 500);
    final result = analysis.add(frame(509, meterRms: .5));
    expect(result['state'], 'ready');
    expect(result['progress'], 1);
    expect(result['noiseDbfs'], closeTo(-40, 1e-10));
    expect(result['offset'], 2);
    expect(result['calibrationValid'], true);
    expect(result['provenance'], 'relative_input');
    collect(analysis, start: 510, count: 600, power: .1);
    expect(analysis.snapshot['progress'], 1);
    expect(analysis.snapshot['offset'], 2);
  });

  test(
    'offset is rounded to one decimal and bounded between zero and three',
    () {
      for (final (dbfs, offset) in [(-90.0, 0.0), (-44.4, 1.6), (-10.0, 3.0)]) {
        final analysis = NativeLevelAnalysis()..sample();
        collect(analysis, power: math.pow(10, dbfs / 10).toDouble());
        expect(analysis.snapshot['noiseDbfs'], closeTo(dbfs, 1e-10));
        expect(analysis.snapshot['offset'], offset);
      }
    },
  );

  test('median and quartile checks match the web estimator', () {
    final analysis = NativeLevelAnalysis()..sample();
    collect(analysis, count: 250, power: .00001);
    collect(analysis, start: 250, count: 250, power: .00002);
    expect(analysis.snapshot['state'], 'ready');
    expect(
      analysis.snapshot['noiseDbfs'],
      closeTo(10 * math.log(.000015) / math.ln10, 1e-10),
    );
    analysis.sample();
    collect(analysis, start: 500, count: 250, power: .000001);
    collect(analysis, start: 750, count: 250, power: .001);
    expect(analysis.snapshot['state'], 'failed');
    expect(analysis.snapshot['reason'], 'unstable_environment');
    expect(analysis.snapshot['calibrationValid'], true);
    expect(
      analysis.snapshot['noiseDbfs'],
      closeTo(10 * math.log(.000015) / math.ln10, 1e-10),
    );
  });

  test('cancel preserves an earlier successful result and resets progress', () {
    final analysis = NativeLevelAnalysis()..sample();
    collect(analysis, count: 30);
    analysis.cancel();
    expect(analysis.snapshot['state'], 'idle');
    expect(analysis.snapshot['progress'], 0);
    expect(analysis.snapshot['calibrationValid'], false);
    analysis.sample();
    collect(analysis, start: 30);
    analysis.sample();
    collect(analysis, start: 530, count: 20, power: .001);
    analysis.cancel();
    expect(analysis.snapshot['state'], 'ready');
    expect(analysis.snapshot['offset'], 2);
    expect(analysis.snapshot['meterDbfs'], null);
    expect(analysis.snapshot['progress'], 0);
  });

  test(
    'clipping and missing nonzero samples fail without replacing calibration',
    () {
      final analysis = NativeLevelAnalysis()..sample();
      collect(analysis);
      analysis.sample();
      collect(analysis, start: 500, count: 50, clipped: true);
      collect(analysis, start: 550, count: 450);
      expect(analysis.snapshot['reason'], 'clipping');
      expect(analysis.snapshot['offset'], 2);
      analysis.sample();
      collect(analysis, start: 1000, count: 399);
      collect(analysis, start: 1399, count: 101, power: 0);
      expect(analysis.snapshot['reason'], 'insufficient_samples');
      expect(analysis.snapshot['offset'], 2);
    },
  );

  test('zero input never produces a valid environment', () {
    final analysis = NativeLevelAnalysis()..sample();
    collect(analysis, power: 0);
    expect(analysis.snapshot['state'], 'failed');
    expect(analysis.snapshot['calibrationValid'], false);
    expect(analysis.snapshot['noiseDbfs'], null);
  });

  test('excluded queued frames and duplicates do not advance sampling', () {
    final analysis = NativeLevelAnalysis()..sample();
    analysis.add(frame(0), collect: false);
    expect(analysis.snapshot['progress'], 0);
    analysis.add(frame(1));
    analysis.add(frame(1));
    analysis.add(frame(0));
    expect(analysis.snapshot['progress'], 1 / 500);
    analysis.sample();
    expect(analysis.snapshot['progress'], 1 / 500);
  });

  test(
    'sequence gaps invalidate calibration and restart speech confirmation',
    () {
      final analysis = NativeLevelAnalysis()..sample();
      collect(analysis);
      for (var seq = 500; seq < 503; seq++) {
        analysis.add(frame(seq, speech: 'speech'));
      }
      expect(analysis.snapshot['meterState'], 'speech');
      analysis.add(frame(504, speech: 'speech'));
      expect(analysis.snapshot['calibrationValid'], false);
      expect(analysis.snapshot['reason'], 'input_gap');
      expect(analysis.snapshot['meterState'], 'confirming');
      expect(analysis.snapshot['meterDbfs'], null);
      analysis.add(frame(505, speech: 'speech'));
      analysis.add(frame(506, speech: 'speech'));
      expect(analysis.snapshot['meterState'], 'speech');
    },
  );

  test(
    'meter requires three positive speech frames and clears on uncertainty',
    () {
      final analysis = NativeLevelAnalysis();
      expect(analysis.add(frame(0))['meterState'], 'nonSpeech');
      expect(
        analysis.add(frame(1, speech: 'speech'))['meterState'],
        'confirming',
      );
      expect(analysis.add(frame(2, speech: 'speech'))['meterDbfs'], null);
      expect(
        analysis.add(frame(3, speech: 'speech'))['meterDbfs'],
        closeTo(-40, 1e-10),
      );
      expect(analysis.add(frame(4, speech: 'uncertain'))['meterDbfs'], null);
      expect(
        analysis.add(frame(5, speech: 'speech'))['meterState'],
        'confirming',
      );
      final clipped = analysis.add(frame(6, speech: 'speech', clipped: true));
      expect(clipped['speech'], 'uncertain');
      expect(clipped['meterState'], 'unavailable');
      final zero = analysis.add(frame(7, speech: 'speech', meterRms: 0));
      expect(zero['meterState'], 'unavailable');
      expect(zero['meterDbfs'], null);
    },
  );

  test('sampling hides meter values and cancellation starts a new onset', () {
    final analysis = NativeLevelAnalysis();
    for (var seq = 0; seq < 3; seq++) {
      analysis.add(frame(seq, speech: 'speech'));
    }
    expect(analysis.snapshot['meterState'], 'speech');
    analysis.sample();
    expect(analysis.snapshot['meterState'], 'calibrating');
    expect(analysis.snapshot['meterDbfs'], null);
    analysis.add(frame(3, speech: 'speech'));
    expect(analysis.snapshot['meterState'], 'calibrating');
    analysis.cancel();
    expect(analysis.snapshot['meterState'], 'unavailable');
    expect(
      analysis.add(frame(4, speech: 'speech'))['meterState'],
      'confirming',
    );
  });

  test('invalidation clears result and meter without resetting sequence', () {
    final analysis = NativeLevelAnalysis()..sample();
    collect(analysis);
    analysis.invalidate('analysis_stale');
    expect(analysis.snapshot['calibrationValid'], false);
    expect(analysis.snapshot['state'], 'failed');
    expect(analysis.snapshot['reason'], 'analysis_stale');
    expect(analysis.snapshot['meterDbfs'], null);
    analysis.add(frame(499));
    expect(analysis.snapshot['reason'], 'analysis_stale');
  });

  test('malformed native frames throw before changing state', () {
    final analysis = NativeLevelAnalysis()..sample();
    final before = analysis.snapshot;
    for (final invalid in <Map<String, Object?>>[
      {...frame(0), 'seq': -1},
      {...frame(0), 'seq': 0.5},
      {...frame(0), 'seq': double.infinity},
      {...frame(0), 'seq': 9007199254740992},
      {...frame(0), 'power': -1},
      {...frame(0), 'power': double.nan},
      {...frame(0), 'meterRms': double.infinity},
      {...frame(0), 'meterRms': -1},
      {...frame(0), 'speech': 'yes'},
      {...frame(0), 'clipped': 0},
      frame(0)..remove('meterRms'),
    ]) {
      expect(() => analysis.add(invalid), throwsArgumentError);
      expect(analysis.snapshot, before);
    }
  });
}
