import 'dart:math' as math;
import 'dart:typed_data';

// A Dart port of VoiceMate's public-method-based JS test implementation.
// Values measure a recording; they are not normal ranges or clinical scores.
const double frameHopSeconds = 0.02;
const double _minPitch = 65;
const double _maxPitch = 500;
const double _minClarity = 0.85;
const double _minLevelDb = -65;
const _unset = Object();

double? median(Iterable<double?> source) {
  final values = source.whereType<double>().where((v) => v.isFinite).toList()
    ..sort();
  if (values.isEmpty) return null;
  final middle = values.length ~/ 2;
  return values.length.isOdd
      ? values[middle]
      : (values[middle - 1] + values[middle]) / 2;
}

class AudioFrame {
  const AudioFrame({
    required this.time,
    this.pitchHz,
    required this.rmsDb,
    required this.active,
    this.clarity = 0,
    this.relativePitch,
    this.relativeDb,
  });
  final double time;
  final double? pitchHz;
  final double rmsDb;
  final bool active;
  final double clarity;
  final double? relativePitch;
  final double? relativeDb;

  double? value(String field) =>
      field == 'relativeDb' ? relativeDb : relativePitch;

  AudioFrame copyWith({
    double? time,
    Object? pitchHz = _unset,
    double? rmsDb,
    bool? active,
    double? clarity,
    Object? relativePitch = _unset,
    Object? relativeDb = _unset,
  }) => AudioFrame(
    time: time ?? this.time,
    pitchHz: identical(pitchHz, _unset)
        ? this.pitchHz
        : (pitchHz as num?)?.toDouble(),
    rmsDb: rmsDb ?? this.rmsDb,
    active: active ?? this.active,
    clarity: clarity ?? this.clarity,
    relativePitch: identical(relativePitch, _unset)
        ? this.relativePitch
        : (relativePitch as num?)?.toDouble(),
    relativeDb: identical(relativeDb, _unset)
        ? this.relativeDb
        : (relativeDb as num?)?.toDouble(),
  );
}

class AudioAnalysis {
  AudioAnalysis({
    required List<AudioFrame> frames,
    required this.duration,
    double? recordingDuration,
    this.startTime = 0,
    this.pitchMedian,
    this.levelMedian,
    int? voicedFrames,
    double? voicedDuration,
    this.sampleRate = 16000,
    this.noiseFloor,
    this.activeFloor = _minLevelDb,
  }) : frames = List.unmodifiable(frames),
       recordingDuration = recordingDuration ?? duration,
       voicedFrames =
           voicedFrames ??
           frames.where((f) => f.active && f.pitchHz != null).length,
       voicedDuration =
           voicedDuration ??
           math.min(
             duration,
             frames.where((f) => f.active && f.pitchHz != null).length *
                 frameHopSeconds,
           );
  final List<AudioFrame> frames;
  final double duration;
  final double recordingDuration;
  final double startTime;
  final double? pitchMedian;
  final double? levelMedian;
  final int voicedFrames;
  final double voicedDuration;
  final int sampleRate;
  final double? noiseFloor;
  final double activeFloor;
  double get excludedDuration =>
      math.max(0, recordingDuration - voicedDuration);
  double get voicedFraction =>
      frames.isEmpty ? 0 : voicedFrames / frames.length;
}

typedef FramePair = (int, int);

class Comparison {
  const Comparison({
    required this.path,
    this.pitchError,
    this.intensityError,
    this.voicedPairs = 0,
    this.durationRatio,
    this.warnings = const [],
  });
  final List<FramePair> path;
  final double? pitchError;
  final double? intensityError;
  final int voicedPairs;
  final double? durationRatio;
  final List<String> warnings;
  double? get error => pitchError;
}

class Segment {
  const Segment({
    required this.label,
    required this.start,
    required this.end,
    required this.userStart,
    required this.userEnd,
    required this.pairs,
    this.pitchError,
    this.levelError,
    this.pitchDelta,
    this.levelDelta,
    this.matchedReferenceFrames = 0,
    this.matchedUserFrames = 0,
  });
  final String label;
  final double start, end, userStart, userEnd;
  final int pairs, matchedReferenceFrames, matchedUserFrames;
  final double? pitchError, levelError, pitchDelta, levelDelta;
}

class DurationComparison {
  const DurationComparison(
    this.reference,
    this.user,
    this.referenceRecording,
    this.userRecording,
    this.referenceSpan,
    this.userSpan,
  );
  final double reference,
      user,
      referenceRecording,
      userRecording,
      referenceSpan,
      userSpan;
  double get referenceExcluded => math.max(0, referenceRecording - reference);
  double get userExcluded => math.max(0, userRecording - user);
}

class ComparisonSummary {
  const ComparisonSummary({
    required this.segments,
    required this.duration,
    required this.pitchReliable,
  });
  final List<Segment> segments;
  final DurationComparison duration;
  final bool pitchReliable;
}

class _Reduced {
  const _Reduced(this.samples, this.rate);
  final List<double> samples;
  final double rate;
}

_Reduced _downsample(List<double> input, int sampleRate) {
  final factor = math.max(1, sampleRate ~/ 12000);
  if (factor == 1) return _Reduced(input, sampleRate.toDouble());
  final out = Float64List(input.length ~/ factor);
  for (var i = 0; i < out.length; i++) {
    var sum = 0.0;
    for (var j = 0; j < factor; j++) {
      final value = input[i * factor + j];
      sum += value.isFinite ? value : 0;
    }
    out[i] = sum / factor;
  }
  return _Reduced(out, sampleRate / factor);
}

({double? pitchHz, double clarity}) _yin(List<double> frame, double rate) {
  final maxLag = math.min((rate / _minPitch).floor(), frame.length ~/ 2 - 1);
  final minLag = math.max(2, (rate / _maxPitch).floor());
  if (maxLag <= minLag) return (pitchHz: null, clarity: 0);
  final difference = Float64List(maxLag + 1);
  final half = frame.length ~/ 2;
  for (var lag = 1; lag <= maxLag; lag++) {
    var sum = 0.0;
    for (var i = 0; i < half; i++) {
      final d = frame[i] - frame[i + lag];
      sum += d * d;
    }
    difference[lag] = sum;
  }
  final normalized = Float64List(maxLag + 1)..[0] = 1;
  var running = 0.0;
  for (var lag = 1; lag <= maxLag; lag++) {
    running += difference[lag];
    normalized[lag] = running > 1e-12 ? difference[lag] * lag / running : 1;
  }
  var chosen = -1;
  for (var lag = minLag; lag < maxLag; lag++) {
    if (normalized[lag] < 0.16) {
      while (lag + 1 <= maxLag && normalized[lag + 1] < normalized[lag]) {
        lag++;
      }
      chosen = lag;
      break;
    }
  }
  if (chosen < 0) return (pitchHz: null, clarity: 0);
  final clarity = (1 - normalized[chosen]).clamp(0.0, 1.0).toDouble();
  var refined = chosen.toDouble();
  if (chosen > 1 && chosen < maxLag) {
    final a = normalized[chosen - 1],
        b = normalized[chosen],
        c = normalized[chosen + 1];
    final denominator = a - 2 * b + c;
    if (denominator.abs() > 1e-12) {
      refined += (0.5 * (a - c) / denominator).clamp(-0.5, 0.5);
    }
  }
  final pitch = rate / refined;
  return (
    pitchHz: pitch.isFinite && pitch >= _minPitch && pitch <= _maxPitch
        ? pitch
        : null,
    clarity: clarity,
  );
}

double _rmsDb(List<double> frame) {
  var energy = 0.0;
  for (final sample in frame) {
    if (sample.isFinite) energy += sample * sample;
  }
  return 20 *
      math.log(math.max(1e-7, math.sqrt(energy / math.max(1, frame.length)))) /
      math.ln10;
}

/// One live frame. This is periodicity measurement, not speaker identification.
AudioFrame analyzeFrame(
  List<double> samples,
  int sampleRate, {
  double? noiseFloorDb,
  double time = 0,
}) {
  if (sampleRate < 8000) throw ArgumentError('샘플 레이트는 8,000Hz 이상이어야 해요.');
  final reduced = _downsample(samples, sampleRate);
  final rmsDb = _rmsDb(reduced.samples);
  final floor = noiseFloorDb != null && noiseFloorDb.isFinite
      ? math.max(_minLevelDb, noiseFloorDb + 6)
      : _minLevelDb;
  final detected = rmsDb >= floor
      ? _yin(reduced.samples, reduced.rate)
      : (pitchHz: null, clarity: 0.0);
  final active = detected.pitchHz != null && detected.clarity >= _minClarity;
  return AudioFrame(
    time: time,
    pitchHz: active ? detected.pitchHz : null,
    rmsDb: rmsDb,
    active: active,
    clarity: detected.clarity,
  );
}

/// 50ms windows / 20ms hops. Absolute signal level is not calibrated dB SPL.
AudioAnalysis analyzeSamples(List<double> input, int sampleRate) {
  if (sampleRate < 8000) throw ArgumentError('샘플 레이트는 8,000Hz 이상이어야 해요.');
  if (input.length / sampleRate > 30) {
    throw RangeError('연습 음성은 30초 이하로 녹음해 주세요.');
  }
  final duration = input.length / sampleRate;
  final reduced = _downsample(input, sampleRate),
      signal = reduced.samples,
      rate = reduced.rate;
  final windowSize = math.max(2, (rate * 0.05).round());
  final hop = math.max(1, (rate * frameHopSeconds).round());
  final frames = <AudioFrame>[];
  for (var start = 0; start + windowSize <= signal.length; start += hop) {
    final frame = signal.sublist(start, start + windowSize);
    final db = _rmsDb(frame);
    final detected = db < _minLevelDb
        ? (pitchHz: null, clarity: 0.0)
        : _yin(frame, rate);
    frames.add(
      AudioFrame(
        time: (start + windowSize / 2) / rate,
        pitchHz: detected.pitchHz,
        rmsDb: db,
        active: false,
        clarity: detected.clarity,
      ),
    );
  }
  final candidates = frames
      .where((f) => f.pitchHz != null && f.clarity >= _minClarity)
      .toList();
  final background =
      frames
          .where((f) => f.pitchHz == null || f.clarity < _minClarity)
          .map((f) => f.rmsDb)
          .toList()
        ..sort();
  final noiseFloor = background.length >= 5
      ? background[((background.length - 1) * 0.2).floor()]
      : null;
  final candidateLevel = median(candidates.map((f) => f.rmsDb));
  final levels = candidates.map((f) => f.rmsDb).toList()..sort();
  final upperVoice =
      median(levels.skip(math.max(0, levels.length - 8))) ?? _minLevelDb;
  final activeFloor = math.max(
    _minLevelDb,
    math.max(
      upperVoice - 30,
      noiseFloor != null && candidateLevel != null
          ? math.min(noiseFloor + 6, candidateLevel - 20)
          : _minLevelDb,
    ),
  );
  for (var i = 0; i < frames.length; i++) {
    final f = frames[i];
    frames[i] = f.copyWith(
      active:
          f.rmsDb >= activeFloor &&
          f.pitchHz != null &&
          f.clarity >= _minClarity,
    );
  }
  for (var start = 0; start < frames.length;) {
    if (!frames[start].active) {
      start++;
      continue;
    }
    var end = start + 1;
    while (end < frames.length && frames[end].active) {
      end++;
    }
    if (end - start < 3) {
      for (var i = start; i < end; i++) {
        frames[i] = frames[i].copyWith(active: false);
      }
    }
    start = end;
  }
  for (var i = 0; i < frames.length; i++) {
    if (!frames[i].active) frames[i] = frames[i].copyWith(pitchHz: null);
  }
  final pitchMedian = median(frames.map((f) => f.pitchHz));
  final levelMedian = median(frames.where((f) => f.active).map((f) => f.rmsDb));
  for (var i = 0; i < frames.length; i++) {
    final f = frames[i];
    frames[i] = f.copyWith(
      relativePitch: f.pitchHz != null && pitchMedian != null
          ? 12 * math.log(f.pitchHz! / pitchMedian) / math.ln2
          : null,
      relativeDb: f.active && levelMedian != null
          ? f.rmsDb - levelMedian
          : null,
    );
  }
  final count = frames.where((f) => f.active).length;
  return AudioAnalysis(
    frames: frames,
    duration: duration,
    recordingDuration: duration,
    sampleRate: sampleRate,
    pitchMedian: pitchMedian,
    levelMedian: levelMedian,
    noiseFloor: noiseFloor,
    activeFloor: activeFloor,
    voicedFrames: count,
    voicedDuration: math.min(duration, count * hop / rate),
  );
}

AudioAnalysis trimAnalysis(AudioAnalysis analysis) {
  final active = analysis.frames.where((f) => f.active).toList();
  if (active.isEmpty) {
    return AudioAnalysis(
      frames: [],
      duration: 0,
      recordingDuration: analysis.recordingDuration,
      sampleRate: analysis.sampleRate,
    );
  }
  final start = math.max(0.0, active.first.time - 0.025);
  final end = math.min(analysis.duration, active.last.time + 0.025);
  return AudioAnalysis(
    frames: analysis.frames
        .where((f) => f.time >= start && f.time <= end)
        .map((f) => f.copyWith(time: f.time - start))
        .toList(),
    duration: end - start,
    recordingDuration: analysis.recordingDuration,
    startTime: analysis.startTime + start,
    pitchMedian: analysis.pitchMedian,
    levelMedian: analysis.levelMedian,
    sampleRate: analysis.sampleRate,
    noiseFloor: analysis.noiseFloor,
    activeFloor: analysis.activeFloor,
    voicedFrames: analysis.voicedFrames,
    voicedDuration: analysis.voicedDuration,
  );
}

double _frameCost(AudioFrame a, AudioFrame b) =>
    math.min(8, (a.relativePitch! - b.relativePitch!).abs()) / 4 +
    0.25 * math.min(18, (a.relativeDb! - b.relativeDb!).abs()) / 6;

/// Constrained DTW only approximates timing. It does not align words.
Comparison compareAnalyses(AudioAnalysis reference, AudioAnalysis user) {
  List<int> sequence(List<AudioFrame> frames) => [
    for (var i = 0; i < frames.length; i++)
      if (frames[i].active &&
          (frames[i].relativePitch?.isFinite ?? false) &&
          (frames[i].relativeDb?.isFinite ?? false))
        i,
  ];
  final r = sequence(reference.frames),
      u = sequence(user.frames),
      n = r.length,
      m = u.length;
  if (n < 8 ||
      m < 8 ||
      reference.pitchMedian == null ||
      user.pitchMedian == null) {
    return const Comparison(
      path: [],
      warnings: ['이번 녹음에서는 비교할 높낮이가 충분히 잡히지 않았어요.'],
    );
  }
  final cols = m + 1,
      costs = Float64List((n + 1) * cols),
      steps = Uint8List((n + 1) * cols);
  costs.fillRange(0, costs.length, double.infinity);
  costs[0] = 0;
  final band = math.max(8, (math.max(n, m) * 0.2).ceil());
  for (var i = 1; i <= n; i++) {
    final center = i * m / n;
    for (
      var j = math.max(1, (center - band).floor());
      j <= math.min(m, (center + band).ceil());
      j++
    ) {
      final at = i * cols + j;
      var best = costs[(i - 1) * cols + j - 1], step = 1;
      final vertical = costs[(i - 1) * cols + j] + 0.18,
          horizontal = costs[i * cols + j - 1] + 0.18;
      if (vertical < best) {
        best = vertical;
        step = 2;
      }
      if (horizontal < best) {
        best = horizontal;
        step = 3;
      }
      if (best.isFinite) {
        costs[at] =
            best +
            _frameCost(reference.frames[r[i - 1]], user.frames[u[j - 1]]);
        steps[at] = step;
      }
    }
  }
  if (!costs[n * cols + m].isFinite) {
    return const Comparison(
      path: [],
      warnings: ['두 녹음의 길이 차이가 커서 비교를 잠시 보류했어요.'],
    );
  }
  var i = n, j = m;
  final path = <FramePair>[];
  while (i > 0 && j > 0) {
    path.add((r[i - 1], u[j - 1]));
    final step = steps[i * cols + j];
    if (step == 1) {
      i--;
      j--;
    } else if (step == 2) {
      i--;
    } else if (step == 3) {
      j--;
    } else {
      break;
    }
  }
  final ordered = path.reversed.toList();
  double symmetricError(String field) {
    final perReference = <int, List<double>>{}, perUser = <int, List<double>>{};
    for (final (ri, ui) in ordered) {
      final error =
          (reference.frames[ri].value(field)! - user.frames[ui].value(field)!)
              .abs();
      (perReference[ri] ??= []).add(error);
      (perUser[ui] ??= []).add(error);
    }
    double mean(Map<int, List<double>> map) =>
        map.values.fold(
          0.0,
          (sum, values) => sum + values.reduce((a, b) => a + b) / values.length,
        ) /
        map.length;
    return (mean(perReference) + mean(perUser)) / 2;
  }

  return Comparison(
    path: ordered,
    pitchError: symmetricError('relativePitch'),
    intensityError: symmetricError('relativeDb'),
    voicedPairs: ordered.length,
    durationRatio: m / n,
  );
}

ComparisonSummary summarizeComparison(
  AudioAnalysis reference,
  AudioAnalysis user,
  Comparison comparison, {
  bool whole = false,
}) {
  final rCount = comparison.path.map((p) => p.$1).toSet().length;
  final uCount = comparison.path.map((p) => p.$2).toSet().length;
  final reliable = comparison.voicedPairs >= 8 && rCount >= 8 && uCount >= 8;
  final ranges = whole
      ? [(label: '선택 구간 전체', start: 0.0, end: reference.duration)]
      : [
          for (var i = 0; i < 3; i++)
            (
              label: ['앞부분', '중간', '끝부분'][i],
              start: reference.duration * i / 3,
              end: reference.duration * (i + 1) / 3,
            ),
        ];
  final segments = <Segment>[];
  for (final range in ranges) {
    final matches = comparison.path
        .where(
          (p) =>
              reference.frames[p.$1].time >= range.start &&
              reference.frames[p.$1].time <= range.end,
        )
        .toList();
    ({double? delta, double? error}) differences(String field) {
      final byR = <int, List<double>>{}, byU = <int, List<double>>{};
      for (final (ri, ui) in matches) {
        final a = reference.frames[ri].value(field),
            b = user.frames[ui].value(field);
        if (a == null || b == null || !a.isFinite || !b.isFinite) continue;
        (byR[ri] ??= []).add(b - a);
        (byU[ui] ??= []).add(b - a);
      }
      if (byR.length < 5 || byU.length < 5) return (delta: null, error: null);
      double absolute(Map<int, List<double>> map) =>
          map.values.fold(
            0.0,
            (sum, values) =>
                sum + values.fold(0.0, (s, v) => s + v.abs()) / values.length,
          ) /
          map.length;
      return (
        delta: median(byU.values.map(median)),
        error: (absolute(byR) + absolute(byU)) / 2,
      );
    }

    final pitch = differences('relativePitch'),
        level = differences('relativeDb');
    final times = matches.map((p) => user.frames[p.$2].time).toList()..sort();
    segments.add(
      Segment(
        label: range.label,
        start: range.start,
        end: range.end,
        userStart: times.isEmpty ? 0 : times.first,
        userEnd: times.isEmpty ? 0 : times.last,
        pairs: matches.length,
        pitchDelta: reliable ? pitch.delta : null,
        pitchError: reliable ? pitch.error : null,
        levelDelta: level.delta,
        levelError: level.error,
        matchedReferenceFrames: matches.map((p) => p.$1).toSet().length,
        matchedUserFrames: matches.map((p) => p.$2).toSet().length,
      ),
    );
  }
  return ComparisonSummary(
    segments: segments,
    pitchReliable: reliable,
    duration: DurationComparison(
      reference.voicedDuration,
      user.voicedDuration,
      reference.recordingDuration,
      user.recordingDuration,
      reference.duration,
      user.duration,
    ),
  );
}

List<AudioFrame> alignedTrace(
  AudioAnalysis reference,
  AudioAnalysis user,
  List<FramePair> path,
) {
  final buckets = List.generate(reference.frames.length, (_) => <AudioFrame>[]);
  for (final (ri, ui) in path) {
    buckets[ri].add(user.frames[ui]);
  }
  return [
    for (var i = 0; i < reference.frames.length; i++)
      AudioFrame(
        time: reference.frames[i].time,
        pitchHz: median(buckets[i].map((f) => f.pitchHz)),
        rmsDb: median(buckets[i].map((f) => f.rmsDb)) ?? -140,
        active: buckets[i].isNotEmpty,
        relativePitch: median(buckets[i].map((f) => f.relativePitch)),
        relativeDb: median(buckets[i].map((f) => f.relativeDb)),
      ),
  ];
}

/// Crop a manually selected time interval; keep the original playback offset.
AudioAnalysis cropReferenceAnalysis(
  AudioAnalysis source, {
  required double start,
  required double end,
}) {
  if (!start.isFinite ||
      !end.isFinite ||
      start < 0 ||
      end <= start ||
      end > source.duration + 1e-9) {
    throw ArgumentError('가이드 안에서 시작보다 뒤에 있는 끝 시간을 골라 주세요.');
  }
  final boundedEnd = math.min(end, source.duration),
      duration = boundedEnd - start;
  final selected = source.frames
      .where((f) => f.time >= start - 1e-9 && f.time <= boundedEnd + 1e-9)
      .toList();
  final active = selected
      .where(
        (f) =>
            f.active &&
            f.pitchHz != null &&
            f.pitchHz!.isFinite &&
            f.pitchHz! > 0 &&
            f.rmsDb.isFinite,
      )
      .toList();
  final pitch = median(active.map((f) => f.pitchHz)),
      level = median(active.map((f) => f.rmsDb));
  if (active.length < 8 || pitch == null || level == null) {
    throw StateError('이 구간에서 비교할 목소리가 충분하지 않아요. 조금 더 넓은 구간을 골라 주세요.');
  }
  final frames = selected.map((f) {
    final valid =
        f.active &&
        f.pitchHz != null &&
        f.pitchHz!.isFinite &&
        f.pitchHz! > 0 &&
        f.rmsDb.isFinite;
    return f.copyWith(
      time: (f.time - start).clamp(0.0, duration).toDouble(),
      active: valid,
      pitchHz: valid ? f.pitchHz : null,
      relativePitch: valid
          ? 12 * math.log(f.pitchHz! / pitch) / math.ln2
          : null,
      relativeDb: valid ? f.rmsDb - level : null,
    );
  }).toList();
  return AudioAnalysis(
    frames: frames,
    duration: duration,
    recordingDuration: duration,
    startTime: source.startTime + start,
    sampleRate: source.sampleRate,
    pitchMedian: pitch,
    levelMedian: level,
    voicedFrames: active.length,
    voicedDuration: math.min(duration, active.length * frameHopSeconds),
    noiseFloor: source.noiseFloor,
    activeFloor: source.activeFloor,
  );
}
