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
const _roundingNote = '수치는 0.1 단위로 반올림했어요. 앞·뒤 대표값의 비교이며 중간 흐름 전체를 뜻하지 않아요.';

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
  _Change(this.delta);
  final double delta;
  double get shown => (delta * 10).round() / 10;
  String get direction => shown > 0
      ? 'rise'
      : shown < 0
      ? 'fall'
      : 'rounded-zero';
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
  final first = frames
      .where((f) => f.time <= start + third + _epsilon)
      .toList();
  final last = frames.where((f) => f.time >= end - third - _epsilon).toList();
  if (!_endpointSupport(first) || !_endpointSupport(last)) return null;
  return _Change(
    median(last.map((f) => _value(f, volume)))! -
        median(first.map((f) => _value(f, volume)))!,
  );
}

PracticeFeedback _unavailable() => const PracticeFeedback(
  title: '이 부분은 측정이 충분하지 않았어요',
  observation: '구간의 앞쪽과 뒤쪽에서 비교에 필요한 음성 값을 충분히 얻지 못했어요.',
  action: '마이크 연결과 녹음 환경을 확인한 뒤 다시 녹음해 보세요.',
  available: false,
  cardLabel: '측정 대기',
  icon: '?',
  tone: 'uncertain',
  detail: '측정 근거가 부족해 변화 방향을 안내하지 않았어요.',
);

String _qualitative(_Change change, bool volume) {
  if (change.direction == 'rounded-zero') return '앞·뒤 대표값의 차이가 작게 표시됐어요';
  final motion = volume
      ? (change.direction == 'rise' ? '커요' : '작아요')
      : (change.direction == 'rise' ? '높아요' : '낮아요');
  return '뒤쪽의 ${volume ? '소리가' : '음이'} 앞쪽보다 $motion';
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
  var tone = 'neutral', title = '이번 흐름을 살펴봐요', cardLabel = '흐름 살펴보기';
  var observation =
      '이번 녹음은 ${_qualitative(u, volume)}. 예시와 나란히 보며 변화를 확인할 수 있어요.';
  var action = '파란 선과 주황 선을 보며 이 구간의 변화를 살펴보세요. 필요하면 해당 부분만 다시 읽어도 좋아요.';
  if (same) {
    tone = 'encourage';
    title = '같은 방향을 만들었어요';
    cardLabel = '같은 방향';
    observation = '앞·뒤 변화 방향은 예시와 같아요. 이번 녹음은 ${_qualitative(u, volume)}.';
    action = '변화의 크기까지 똑같이 맞추지 않아도 괜찮아요. 지금 만든 방향으로 다시 읽거나 다음 구간으로 넘어가도 좋아요.';
  } else if (opposite ||
      (r.direction != 'rounded-zero' && u.direction == 'rounded-zero')) {
    tone = 'practice';
    title = '한 부분씩 연습해 봐요';
    cardLabel = '한 부분씩 연습';
    observation =
        '예시는 ${_qualitative(r, volume)}. 이번 녹음은 ${_qualitative(u, volume)}.';
    final movement = volume
        ? (r.direction == 'rise' ? '키워서' : '줄여서')
        : (r.direction == 'rise' ? '높여서' : '낮춰서');
    action =
        '이 예시를 따라 연습하려면, 파란 선을 보며 이 구간의 끝 ${volume ? '소리를' : '음을'} 조금 $movement 읽어 보세요.';
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
        '예시는 ${_numeric(r, volume)}. 내 녹음은 ${_numeric(u, volume)}. $_roundingNote${volume ? ' 크기는 녹음별 상대값이며 실제 소음계 데시벨이 아니에요.' : ''}',
  );
}
