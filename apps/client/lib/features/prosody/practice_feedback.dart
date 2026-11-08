import 'audio/audio_analysis.dart';

/// Practice prompts about a selected reference example. These do not grade
/// naturalness, pronunciation or communication ability.
class PracticeFeedback {
  const PracticeFeedback({
    required this.title,
    required this.observation,
    required this.action,
    required this.available,
    required this.cardLabel,
    required this.icon,
    required this.detail,
    this.tone = 'neutral',
    this.referenceDelta,
    this.userDelta,
  });
  final String title, observation, action, cardLabel, icon, detail, tone;
  final bool available;
  final double? referenceDelta, userDelta;
}

// Engineering support requirements for representative endpoint measurements;
// never normal ranges, perceptual thresholds or a validated clinical rubric.
const _epsilon = 1e-8;
const _roundingNote = '목소리가 잡힌 앞·뒤 구간을 비교해 소수 첫째 자리까지 표시한다.';

bool _valid(AudioFrame frame, bool volume) =>
    frame.active &&
    frame.time.isFinite &&
    frame.pitchHz != null &&
    frame.pitchHz!.isFinite &&
    frame.pitchHz! > 0 &&
    _value(frame, volume) != null &&
    _value(frame, volume)!.isFinite;

double? _value(AudioFrame frame, bool volume) =>
    volume ? frame.relativeDb : frame.relativePitch;

bool _range(double start, double end) =>
    start.isFinite && end.isFinite && start >= 0 && end > start;

bool _endpointSupport(List<AudioFrame> frames) {
  if (frames.length < 3 ||
      frames.last.time - frames.first.time + _epsilon < .04) {
    return false;
  }
  for (var i = 1; i < frames.length; i++) {
    if (frames[i].time - frames[i - 1].time > .08 + _epsilon) return false;
  }
  return true;
}

class _Change {
  _Change(this.delta, this.first, this.last);
  final double delta;
  final List<AudioFrame> first, last;
  double get shown => (delta * 10).round() / 10;
  String get direction => shown > 0
      ? 'rise'
      : shown < 0
      ? 'fall'
      : 'rounded-zero';
}

// Select by time and available evidence only. A natural unvoiced consonant
// elsewhere in an endpoint band must not invalidate a measured voice block.
// Missing samples remain missing: there is no interpolation or gap filling.
List<List<AudioFrame>> _supportedBlocks(Iterable<AudioFrame> points) {
  final blocks = <List<AudioFrame>>[];
  for (final frame in points) {
    if (blocks.isEmpty || frame.time - blocks.last.last.time > .08 + _epsilon) {
      blocks.add(<AudioFrame>[]);
    }
    blocks.last.add(frame);
  }
  return blocks.where(_endpointSupport).toList();
}

_Change? _change(Iterable<AudioFrame> source, bool volume) {
  final byTime = <double, AudioFrame>{};
  for (final frame in source) {
    if (_valid(frame, volume)) byTime[frame.time] = frame;
  }
  final frames = byTime.values.toList()
    ..sort((a, b) => a.time.compareTo(b.time));
  if (frames.length < 5 ||
      frames.last.time - frames.first.time + _epsilon < .12) {
    return null;
  }
  final start = frames.first.time, end = frames.last.time;
  final third = (end - start) / 3;
  final startBlocks = _supportedBlocks(
    frames.where((f) => f.time <= start + third + _epsilon),
  );
  final endBlocks = _supportedBlocks(
    frames.where((f) => f.time >= end - third - _epsilon),
  );
  if (startBlocks.isEmpty || endBlocks.isEmpty) return null;
  // The earliest supported block and latest supported block are independent.
  // Their value/direction never influences selection or the range partition.
  final first = startBlocks.first, last = endBlocks.last;
  if (first.last.time >= last.first.time - _epsilon) return null;
  return _Change(
    median(last.map((f) => _value(f, volume)))! -
        median(first.map((f) => _value(f, volume)))!,
    first,
    last,
  );
}

PracticeFeedback _unavailable() => const PracticeFeedback(
  title: '이 부분은 같이 살펴볼까요?',
  observation: '앱이 이 부분의 처음과 끝을 충분히 비교하지 못했어요.',
  action: '그래프를 보며 이 부분을 조금 더 길게 읽어 볼까요? 편한 속도로 해 주세요.',
  available: false,
  cardLabel: '비교 자료 부족',
  icon: '?',
  tone: 'uncertain',
  detail: '서로 겹치지 않는 앞·뒤 음성 구간이 필요해요. 없는 목소리 값을 채우거나 성공·실패로 판단하지 않았어요.',
);

/// Select the finest supported guide-only partition: thirds, halves, whole.
/// User pitch, agreement and comparison errors must never select boundaries.
/// Both sides still need independent matched support in [practiceFeedback].
ComparisonSummary buildPracticeSummary(
  AudioAnalysis reference,
  AudioAnalysis user,
  Comparison comparison, {
  bool whole = false,
}) {
  List<ComparisonRange> rangesFor(int count) => [
    for (var i = 0; i < count; i++)
      ComparisonRange(
        count == 1
            ? (whole ? '선택 구간 전체' : '전체 흐름')
            : count == 2
            ? ['앞부분', '뒷부분'][i]
            : ['앞부분', '중간', '끝부분'][i],
        reference.duration * i / count,
        reference.duration * (i + 1) / count,
      ),
  ];
  bool supports(ComparisonRange range) {
    final frames = reference.frames.where(
      (frame) =>
          frame.time >= range.start - _epsilon &&
          frame.time <= range.end + _epsilon,
    );
    return _change(frames, false) != null && _change(frames, true) != null;
  }

  var ranges = rangesFor(1), supported = false;
  for (final count in whole ? [1] : [3, 2, 1]) {
    final candidate = rangesFor(count);
    if (candidate.every(supports)) {
      ranges = candidate;
      supported = true;
      break;
    }
  }
  final note = !supported
      ? '이 예시에서는 앞·뒤 변화를 안내할 자료가 부족해요. 전체 그래프를 보며 연습할 수 있어요.'
      : ranges.length == 3
      ? '앞·중간·끝은 예시의 시간을 나눈 연습 구간이에요. 단어나 음절을 인식한 결과는 아니에요.'
      : ranges.length == 2
      ? '예시의 목소리를 충분히 비교할 수 있도록 앞·뒤 두 구간으로 나눴어요.'
      : whole
      ? '선택한 구간을 잘게 나누지 않고 하나의 흐름으로 비교해요.'
      : '짧은 예시는 잘게 나누지 않고 전체 흐름을 비교해요.';
  return summarizeComparison(
    reference,
    user,
    comparison,
    ranges: ranges,
    segmentationNote: note,
  );
}

String _qualitative(_Change change, bool volume) {
  if (change.direction == 'rounded-zero') return '처음과 끝의 차이가 작게 표시됐어요';
  final motion = volume
      ? (change.direction == 'rise' ? '커요' : '작아요')
      : (change.direction == 'rise' ? '높아요' : '낮아요');
  return '끝의 ${volume ? '소리가' : '음이'} 처음보다 $motion';
}

String _numeric(_Change change, bool volume) {
  final unit = volume ? 'dB' : '반음';
  if (change.direction == 'rounded-zero') {
    return '앞·뒤 대표값의 차이가 반올림하면 0.0$unit이에요';
  }
  final motion = volume
      ? (change.direction == 'rise' ? '커요' : '작아요')
      : (change.direction == 'rise' ? '높아요' : '낮아요');
  return '뒤쪽의 대표 ${volume ? '상대 크기' : '높이'}가 앞쪽보다 ${change.shown.abs().toStringAsFixed(1)}$unit $motion';
}

String _windows(_Change change) =>
    '앞 ${change.first.first.time.toStringAsFixed(2)}~${change.first.last.time.toStringAsFixed(2)}초, '
    '뒤 ${change.last.first.time.toStringAsFixed(2)}~${change.last.last.time.toStringAsFixed(2)}초';

/// Each side uses chronological unique DTW-matched observations, with the
/// same supported-boundary definition on reference and user. The selected
/// range is a time interval, not an automatically recognized word/syllable.
PracticeFeedback practiceFeedback(
  AudioAnalysis reference,
  AudioAnalysis user,
  Comparison comparison,
  Segment segment, {
  bool volume = false,
}) {
  if (!_range(segment.start, segment.end) ||
      !_range(segment.userStart, segment.userEnd)) {
    return _unavailable();
  }
  final refFrames = <int, AudioFrame>{}, userFrames = <int, AudioFrame>{};
  final seen = <FramePair>{};
  for (final pair in comparison.path) {
    final (ri, ui) = pair;
    if (ri < 0 ||
        ui < 0 ||
        ri >= reference.frames.length ||
        ui >= user.frames.length ||
        !seen.add(pair)) {
      continue;
    }
    final a = reference.frames[ri], b = user.frames[ui];
    if (!_valid(a, volume) ||
        !_valid(b, volume) ||
        a.time < segment.start - _epsilon ||
        a.time > segment.end + _epsilon ||
        b.time < segment.userStart - _epsilon ||
        b.time > segment.userEnd + _epsilon) {
      continue;
    }
    refFrames[ri] = a;
    userFrames[ui] = b;
  }
  final r = _change(refFrames.values, volume),
      u = _change(userFrames.values, volume);
  if (r == null || u == null) return _unavailable();
  final same = r.direction != 'rounded-zero' && r.direction == u.direction;
  final opposite =
      r.direction != 'rounded-zero' &&
      u.direction != 'rounded-zero' &&
      r.direction != u.direction;
  var tone = 'neutral', title = '내 목소리의 흐름을 같이 살펴봐요', cardLabel = '함께 살펴봐요';
  var observation =
      '이번에는 ${_qualitative(u, volume)}. 중간의 움직임은 그래프에서 함께 볼 수 있어요.';
  var action = '파란 선과 주황 선을 나란히 봐 주세요. 더 연습하고 싶은 부분이 있다면, 그 부분만 다시 읽어도 좋아요.';
  if (same) {
    tone = 'encourage';
    final movement = volume
        ? (u.direction == 'rise' ? '크게' : '작게')
        : (u.direction == 'rise' ? '올려' : '내려');
    title = '좋아요! 끝을 $movement 읽었네요.';
    cardLabel = volume
        ? '끝을 $movement 읽었어요'
        : (u.direction == 'rise' ? '끝을 올렸어요' : '끝을 내렸어요');
    observation =
        '${segment.label}에서 ${_qualitative(u, volume)}. 파란 예시도 같은 쪽으로 움직여요.';
    action = '지금처럼 편하게 읽어 보세요. 다음 부분도 같이 해 볼까요?';
  } else if (opposite ||
      (r.direction != 'rounded-zero' && u.direction == 'rounded-zero')) {
    tone = 'practice';
    title = '끝부분만 조금 바꿔 볼까요?';
    cardLabel = '조금씩 연습해요';
    observation =
        '${segment.label}에서 ${_qualitative(u, volume)}. 파란 예시는 ${_qualitative(r, volume)}.';
    final movement = volume
        ? (r.direction == 'rise' ? '키워서' : '줄여서')
        : (r.direction == 'rise' ? '높여서' : '낮춰서');
    action =
        '파란 선을 보면서 끝 ${volume ? '소리를' : '음을'} 조금 $movement 읽어 볼까요? 편하게 한 번 더 해 봐요.';
  }
  return PracticeFeedback(
    title: title,
    observation: observation,
    action: action,
    available: true,
    cardLabel: cardLabel,
    tone: tone,
    icon: u.direction == 'rise'
        ? '↗'
        : u.direction == 'fall'
        ? '↘'
        : '↔',
    referenceDelta: r.delta,
    userDelta: u.delta,
    detail:
        '예시는 ${_numeric(r, volume)}. 내 녹음은 ${_numeric(u, volume)}. '
        '측정 구간: 예시 ${_windows(r)} / 내 녹음 ${_windows(u)}. '
        '$_roundingNote${volume ? ' 크기는 각 녹음의 중간값을 기준으로 한 상대 dB다.' : ''}',
  );
}
