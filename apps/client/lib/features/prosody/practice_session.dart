import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio/audio_analysis.dart';
import 'audio/wav.dart';
import 'practice_feedback.dart';
import 'services/device_audio.dart';

enum PracticePhase {
  idle,
  loading,
  requesting,
  recording,
  processing,
  generating,
  cancelling,
}

class ReferenceClip {
  const ReferenceClip(this.text, this.path, this.analysis, this.source);
  final String text, path, source;
  final AudioAnalysis analysis;
}

class PracticeResult {
  const PracticeResult(
    this.audio,
    this.analysis,
    this.comparison,
    this.summary,
    this.trace, {
    this.demo = false,
  });
  final RecordedAudio audio;
  final AudioAnalysis analysis;
  final Comparison comparison;
  final ComparisonSummary summary;
  final List<AudioFrame> trace;
  final bool demo;
}

AudioAnalysis _analyse((List<double>, int) input) =>
    trimAnalysis(analyzeSamples(input.$1, input.$2));

/// Stateful native practice flow. Audio permissions belong to the service;
/// neither a failed retry nor a failed guide replaces an accepted recording.
class PracticeSession extends ChangeNotifier {
  PracticeSession({DeviceAudioService? audio})
    : audio = audio ?? DeviceAudioService() {
    _errors = this.audio.errors.listen((message) {
      if (!_closed) {
        status = message;
        notifyListeners();
      }
    });
  }
  final DeviceAudioService audio;
  static const presetTexts = ['안녕하세요.', '선글라스', '잠시 말씀드릴게요.'];
  static const presetFiles = ['hello', 'sunglasses', 'phrase'];
  final Map<int, ReferenceClip> _presets = {}, _custom = {};
  List<String> customPhrases = [];
  bool usingScript = false, volume = false;
  int index = 0, selected = 0, _generation = 0;
  bool _closed = false;
  PracticePhase phase = PracticePhase.idle;
  String status = '가이드의 파란 선을 보고 같은 문구를 읽어 보세요.';
  ReferenceClip? reference, _wholeReference;
  PracticeResult? result;
  StreamSubscription<String>? _errors;
  Timer? _timer;
  final Stopwatch _clock = Stopwatch();
  final List<double> _liveSamples = [];
  final List<AudioFrame> _liveFrames = [];
  List<AudioFrame> liveTrace = [];
  int _nextFrameEnd = 800;
  double? _firstVoice;
  double seconds = 0, liveDomain = 1.5, pitchBound = 5, levelBound = 10;
  bool currentVoice = false;

  bool get busy => phase != PracticePhase.idle;
  bool get recording => phase == PracticePhase.recording;
  bool get excerpt => _wholeReference != null;
  List<String> get phrases => usingScript ? customPhrases : presetTexts;
  String get phrase => phrases.isEmpty ? '대본을 먼저 넣어 주세요.' : phrases[index];
  List<AudioFrame> get trace =>
      recording ? liveTrace : result?.trace ?? const [];
  Segment? get segment => result?.summary.segments[selected];
  PracticeFeedback? get feedback {
    final r = result, g = reference, s = segment;
    return r == null || g == null || s == null
        ? null
        : practiceFeedback(
            g.analysis,
            r.analysis,
            r.comparison,
            s,
            volume: volume,
          );
  }

  Future<void> initialize() async {
    if (_closed || busy) return;
    final ticket = ++_generation;
    phase = PracticePhase.loading;
    notifyListeners();
    try {
      for (var i = 0; i < presetFiles.length; i++) {
        if (_presets.containsKey(i)) continue;
        final data = await rootBundle.load(
          'assets/prosody/guides/${presetFiles[i]}.wav',
        );
        if (_closed || ticket != _generation) return;
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        final wav = decodeWav(bytes);
        final analysis = await compute(_analyse, (
          wav.samples.toList(),
          wav.sampleRate,
        ));
        if (_closed || ticket != _generation) return;
        final path = await audio.storeAudio(bytes, name: presetFiles[i]);
        if (_closed || ticket != _generation) return;
        _presets[i] = ReferenceClip(
          presetTexts[i],
          path,
          analysis,
          '준비된 한국어 예시',
        );
      }
      if (_closed || ticket != _generation) return;
      if (!usingScript && reference == null) reference = _presets[index];
    } catch (e) {
      if (!_closed && ticket == _generation) {
        status = '예시를 준비하지 못했어요. ${_message(e)}';
      }
    }
    if (!_closed && ticket == _generation) {
      phase = PracticePhase.idle;
      notifyListeners();
    }
  }

  void setMode(bool script) {
    if (busy || usingScript == script) return;
    usingScript = script;
    choose(0);
  }

  void applyScript(String text) {
    if (busy) return;
    try {
      final parsed = splitPracticeScript(text);
      customPhrases = parsed;
      _custom.clear();
      usingScript = true;
      choose(0);
    } catch (e) {
      status = _message(e);
      notifyListeners();
    }
  }

  void choose(int value) {
    if (busy ||
        (phrases.isNotEmpty && (value < 0 || value >= phrases.length))) {
      return;
    }
    _generation++;
    unawaited(audio.stopPlayback());
    index = value;
    selected = 0;
    result = null;
    _wholeReference = null;
    reference = (usingScript ? _custom : _presets)[index];
    status = reference == null
        ? '이 문장의 한국어 가이드를 만들어 주세요.'
        : '파란 가이드 선을 보고 같은 문구를 읽어 보세요.';
    notifyListeners();
  }

  void setVolume(bool value) {
    volume = value;
    notifyListeners();
  }

  void selectRegion(int value) {
    if (busy ||
        result == null ||
        value < 0 ||
        value >= result!.summary.segments.length) {
      return;
    }
    selected = value;
    notifyListeners();
  }

  Future<void> generateGuide() async {
    if (busy || phrases.isEmpty) return;
    final ticket = ++_generation;
    phase = PracticePhase.generating;
    status = '기기의 한국어 음성으로 가이드와 그래프를 만들고 있어요.';
    notifyListeners();
    try {
      await audio.stopPlayback();
      if (_closed || ticket != _generation) return;
      final generated = await audio.generateGuide(phrase);
      final wav = decodeWav(generated.bytes);
      if (wav.samples.length / wav.sampleRate > 20) {
        throw const FormatException('문장을 조금 더 짧게 나눠 주세요.');
      }
      final analysis = await compute(_analyse, (
        wav.samples.toList(),
        wav.sampleRate,
      ));
      if (_closed || ticket != _generation) return;
      if (analysis.voicedFrames < 15 || analysis.pitchMedian == null) {
        throw const FormatException(
          '가이드에서 높낮이가 충분히 잡히지 않았어요. 준비된 예시를 이용하거나 짧은 문장으로 다시 만들어 주세요.',
        );
      }
      final next = ReferenceClip(
        phrase,
        generated.path,
        analysis,
        generated.source,
      );
      (usingScript ? _custom : _presets)[index] = next;
      reference = next;
      _wholeReference = null;
      result = null;
      selected = 0;
      status = '가이드가 준비됐어요. 파란 선을 보고 같은 문장을 읽어 보세요.';
    } catch (e) {
      if (ticket == _generation) {
        status = '${_message(e)}${reference != null ? ' 기존 가이드는 유지했어요.' : ''}';
      }
    } finally {
      if (!_closed && ticket == _generation) {
        phase = PracticePhase.idle;
        notifyListeners();
      }
    }
  }

  Future<void> startRecording() async {
    if (busy || reference == null) return;
    final ticket = ++_generation;
    phase = PracticePhase.requesting;
    status = '마이크를 준비하고 있어요.';
    notifyListeners();
    _liveSamples.clear();
    _liveFrames.clear();
    liveTrace = [];
    _firstVoice = null;
    _nextFrameEnd = 800;
    seconds = 0;
    currentVoice = false;
    liveDomain = math.max(1.5, reference!.analysis.duration * 1.1);
    pitchBound = _bound(reference!.analysis.frames, false, 5);
    levelBound = _bound(reference!.analysis.frames, true, 10);
    try {
      await audio.stopPlayback();
      if (_closed || ticket != _generation) return;
      await audio.start(
        onSamples: (samples) {
          if (!_closed && ticket == _generation) _onSamples(samples);
        },
        onLimitReached: () {
          if (!_closed && ticket == _generation) {
            unawaited(stopRecording());
          }
        },
        onError: (message) {
          if (!_closed && ticket == _generation) {
            unawaited(cancelCurrent(message: message));
          }
        },
      );
      if (_closed || ticket != _generation) {
        return;
      }
      phase = PracticePhase.recording;
      _clock.reset();
      _clock.start();
      status = '파란 선과 주황 선을 보며 읽어 보세요. 다 읽으면 녹음 마치기를 눌러 주세요.';
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!_closed && recording) {
          seconds = _clock.elapsedMilliseconds / 1000;
          notifyListeners();
        }
      });
      notifyListeners();
    } catch (e) {
      if (!_closed && ticket == _generation) {
        phase = PracticePhase.idle;
        status = '${_message(e)}${result != null ? ' 이전 결과는 유지했어요.' : ''}';
        notifyListeners();
      }
    }
  }

  void _onSamples(List<double> samples) {
    if (_closed || (phase != PracticePhase.requesting && !recording)) return;
    _liveSamples.addAll(samples);
    while (_nextFrameEnd <= _liveSamples.length) {
      final time = _nextFrameEnd / 16000;
      final frame = analyzeFrame(
        _liveSamples.sublist(_nextFrameEnd - 800, _nextFrameEnd),
        16000,
        time: time,
      );
      if (_firstVoice == null && frame.active) _firstVoice = time;
      if (_firstVoice != null) {
        _liveFrames.add(frame.copyWith(time: time - _firstVoice!));
      }
      _nextFrameEnd += 640;
    }
    final voiced = _liveFrames.where((f) => f.active).toList();
    final basePitch = median(voiced.map((f) => f.pitchHz));
    final baseLevel = median(voiced.map((f) => f.rmsDb));
    liveTrace = _liveFrames
        .map(
          (f) => f.copyWith(
            relativePitch: f.active && basePitch != null
                ? 12 * math.log(f.pitchHz! / basePitch) / math.ln2
                : null,
            relativeDb: f.active && baseLevel != null
                ? f.rmsDb - baseLevel
                : null,
          ),
        )
        .toList();
    currentVoice = _liveFrames.isNotEmpty && _liveFrames.last.active;
    final position = liveTrace.isEmpty ? 0.0 : liveTrace.last.time;
    final baseDomain = math.max(1.5, reference!.analysis.duration * 1.1);
    if (position > liveDomain) {
      liveDomain = (position / baseDomain).ceil() * baseDomain;
    }
    pitchBound = _bound(liveTrace, false, pitchBound);
    levelBound = _bound(liveTrace, true, levelBound);
    notifyListeners();
  }

  double _bound(List<AudioFrame> frames, bool level, double minimum) =>
      frames.fold(
        minimum,
        (bound, frame) => math.max(
          bound,
          ((level ? frame.relativeDb : frame.relativePitch)?.abs() ?? 0) * 1.12,
        ),
      );

  Future<void> stopRecording() async {
    if (!recording) return;
    final ticket = _generation;
    _timer?.cancel();
    _clock.stop();
    phase = PracticePhase.processing;
    status = '녹음한 흐름을 확인하고 있어요.';
    notifyListeners();
    try {
      final recorded = await audio.stop();
      await _acceptRecording(recorded, ticket);
    } catch (e) {
      if (ticket == _generation) {
        status = '${_message(e)}${result != null ? ' 이전 결과는 유지했어요.' : ''}';
      }
    } finally {
      if (!_closed && ticket == _generation) {
        phase = PracticePhase.idle;
        notifyListeners();
      }
    }
  }

  Future<void> _acceptRecording(
    RecordedAudio recorded,
    int ticket, {
    bool demo = false,
  }) async {
    final user = await compute(_analyse, (
      recorded.samples,
      recorded.sampleRate,
    ));
    if (_closed || ticket != _generation) return;
    if (user.voicedFrames < 8 || user.pitchMedian == null) {
      throw const FormatException(
        '앱이 목소리를 충분히 잡지 못했어요. 마이크 위치를 확인하고, 준비되면 편하게 다시 읽어 주세요.',
      );
    }
    final comparison = compareAnalyses(reference!.analysis, user);
    if (comparison.path.isEmpty) {
      throw const FormatException('앱이 비교할 목소리를 충분히 잡지 못했어요. 준비되면 다시 읽어 주세요.');
    }
    final next = PracticeResult(
      recorded,
      user,
      comparison,
      buildPracticeSummary(
        reference!.analysis,
        user,
        comparison,
        whole: excerpt,
      ),
      alignedTrace(reference!.analysis, user, comparison.path),
      demo: demo,
    );
    result = next;
    selected = 0;
    status = demo
        ? '합성 시험 신호로 동작을 보여드려요. 실제 사람의 녹음은 아니에요.'
        : '녹음이 끝났어요. 내 목소리의 움직임을 함께 살펴봐요.';
  }

  Future<void> demo() async {
    if (busy || reference == null) return;
    final ticket = ++_generation;
    phase = PracticePhase.processing;
    notifyListeners();
    try {
      final a = reference!.analysis,
          samples = Float64List((a.duration * 1.15 * 16000).ceil());
      var angle = 0.0;
      for (var i = 0; i < samples.length; i++) {
        final t = i / 16000 / 1.15;
        final idx = (t / .02).round().clamp(0, a.frames.length - 1);
        final f = a.frames[idx];
        if (!f.active || f.pitchHz == null) continue;
        final shift = t > a.duration * .66 ? 3.0 : 0.0;
        angle += 2 * math.pi * f.pitchHz! * math.pow(2, shift / 12) / 16000;
        final gain = math.pow(10, f.rmsDb / 20).toDouble().clamp(.02, .6);
        samples[i] = gain * (.8 * math.sin(angle) + .2 * math.sin(angle * 2));
      }
      final bytes = encodeWav(samples, 16000),
          path = await audio.storeAudio(bytes, name: 'demo');
      await _acceptRecording(
        RecordedAudio(
          samples: samples.toList(),
          sampleRate: 16000,
          path: path,
          bytes: bytes,
        ),
        ticket,
        demo: true,
      );
    } catch (e) {
      if (!_closed && ticket == _generation) status = _message(e);
    } finally {
      if (!_closed && ticket == _generation) {
        phase = PracticePhase.idle;
        notifyListeners();
      }
    }
  }

  Future<void> playGuide({bool region = false}) async {
    final g = reference;
    if (busy || g == null) return;
    final s = region ? segment : null;
    final from = g.analysis.startTime + (s?.start ?? 0);
    final until = g.analysis.startTime + (s?.end ?? g.analysis.duration);
    await _play(g.path, from, until);
  }

  Future<void> playUser({bool region = false}) async {
    final r = result;
    if (busy || r == null) return;
    final s = region ? segment : null;
    await _play(
      r.audio.path,
      r.analysis.startTime + (s?.userStart ?? 0),
      r.analysis.startTime + (s?.userEnd ?? r.analysis.duration),
    );
  }

  Future<void> _play(String path, double start, double end) async {
    try {
      await audio.play(
        path,
        start: Duration(microseconds: (start * 1e6).round()),
        end: Duration(microseconds: (end * 1e6).round()),
      );
    } catch (e) {
      if (!_closed) {
        status = _message(e);
        notifyListeners();
      }
    }
  }

  void practiceSelected() {
    if (busy || reference == null || segment == null || excerpt) return;
    try {
      final s = segment!, g = reference!;
      final cropped = cropReferenceAnalysis(
        g.analysis,
        start: s.start,
        end: s.end,
      );
      _wholeReference = g;
      reference = ReferenceClip(g.text, g.path, cropped, '${s.label} 구간 예시');
      result = null;
      selected = 0;
      status = '${s.label} 구간의 파란 선을 보고 해당 부분만 읽어 보세요.';
      notifyListeners();
    } catch (e) {
      status = _message(e);
      notifyListeners();
    }
  }

  void leaveExcerpt() {
    if (busy || _wholeReference == null) return;
    reference = _wholeReference;
    _wholeReference = null;
    result = null;
    selected = 0;
    status = '전체 문장 가이드로 돌아왔어요.';
    notifyListeners();
  }

  Future<void> cancelCurrent({String? message}) async {
    final ticket = ++_generation;
    _timer?.cancel();
    _clock.stop();
    phase = PracticePhase.cancelling;
    status = '음성 작업을 멈추고 있어요.';
    if (!_closed) notifyListeners();
    await audio.cancelGuide();
    if (_closed || ticket != _generation) return;
    await audio.cancel();
    if (_closed || ticket != _generation) return;
    phase = PracticePhase.idle;
    status = message ?? '음성 작업을 멈췄어요. 이전 결과는 유지했어요.';
    notifyListeners();
  }

  String _message(Object e) => e is FormatException ? e.message : e.toString();
  @override
  void dispose() {
    _closed = true;
    _generation++;
    _timer?.cancel();
    unawaited(_errors?.cancel());
    unawaited(audio.dispose());
    super.dispose();
  }
}

List<String> splitPracticeScript(String text) {
  final source = text.trim();
  if (source.isEmpty) throw const FormatException('연습할 대본을 먼저 넣어 주세요.');
  if (source.runes.length > 2000) {
    throw const FormatException('대본은 2,000자 이하로 넣어 주세요.');
  }
  final sentences = <String>[];
  for (final line in source.split(RegExp(r'[\n\r]+'))) {
    var current = '';
    final chars = line.runes.map(String.fromCharCode).toList();
    for (var i = 0; i < chars.length; i++) {
      current += chars[i];
      final decimal =
          chars[i] == '.' &&
          i > 0 &&
          i + 1 < chars.length &&
          RegExp(r'\d').hasMatch(chars[i - 1]) &&
          RegExp(r'\d').hasMatch(chars[i + 1]);
      if (RegExp(r'[.!?。！？]').hasMatch(chars[i]) && !decimal ||
          current.runes.length >= 100) {
        if (current.trim().isNotEmpty) sentences.add(current.trim());
        current = '';
      }
    }
    if (current.trim().isNotEmpty) sentences.add(current.trim());
  }
  if (sentences.length > 30) {
    throw const FormatException('한 번에 30개 구간까지 연습할 수 있어요.');
  }
  return sentences;
}
