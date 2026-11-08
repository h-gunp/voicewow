import 'dart:math' as math;

/// Consumes disjoint 10 ms frames; raw power calibrates the environment while
/// RNNoise output supplies the displayed speech level.
class NativeLevelAnalysis {
  int _seq = -1, _count = 0, _clipped = 0, _speechFrames = 0;
  final _powers = <double>[];
  String _state = 'idle', _meterState = 'unavailable';
  String? _reason, _speech;
  double? _noiseDbfs, _offset, _meterDbfs;

  Map<String, Object?> get snapshot => {
    'state': _state,
    'calibrationValid': _noiseDbfs != null,
    'progress': _count / 500,
    'noiseDbfs': _noiseDbfs,
    'offset': _offset,
    'reason': _reason,
    'speech': _speech,
    'voiceDbfs': null,
    'meterState': _meterState,
    'meterDbfs': _meterDbfs,
    'provenance': 'relative_input',
  };

  void sample() {
    if (_state == 'collecting') return;
    _state = 'collecting';
    _reason = null;
    _clearCollection();
    _clearMeter('calibrating');
  }

  void cancel() {
    if (_state != 'collecting') return;
    _state = _noiseDbfs == null ? 'idle' : 'ready';
    _reason = null;
    _clearCollection();
    _clearMeter();
  }

  void invalidate(String reason) {
    _state = 'failed';
    _reason = reason;
    _noiseDbfs = _offset = null;
    _clearCollection();
    _clearMeter();
  }

  Map<String, Object?> add(Map<String, Object?> frame, {bool collect = true}) {
    final seq = frame['seq'];
    final power = frame['power'];
    final speech = frame['speech'];
    final clipped = frame['clipped'];
    final meterRms = frame['meterRms'];
    if (seq is! int ||
        seq < 0 ||
        seq > 9007199254740991 ||
        power is! num ||
        !power.isFinite ||
        power < 0 ||
        !const ['speech', 'nonSpeech', 'uncertain'].contains(speech) ||
        clipped is! bool ||
        meterRms is! num ||
        !meterRms.isFinite ||
        meterRms < 0) {
      throw ArgumentError('Invalid native audio analysis frame');
    }
    if (seq <= _seq) return snapshot;
    if (_seq >= 0 && seq != _seq + 1) invalidate('input_gap');
    _seq = seq;
    _speech = clipped ? 'uncertain' : speech as String;
    if (_state == 'collecting' && collect) {
      _count++;
      if (clipped) {
        _clipped++;
      } else if (power > 0) {
        _powers.add(power.toDouble());
      }
      if (_count == 500) _finishCollection();
    }

    final validSpeech = !clipped && _speech == 'speech' && meterRms > 0;
    _speechFrames = validSpeech ? math.min(_speechFrames + 1, 3) : 0;
    _meterState = _state == 'collecting'
        ? 'calibrating'
        : clipped
        ? 'unavailable'
        : _speech != 'speech'
        ? _speech!
        : !validSpeech
        ? 'unavailable'
        : _speechFrames < 3
        ? 'confirming'
        : 'speech';
    _meterDbfs = _meterState == 'speech'
        ? 20 * math.log(meterRms) / math.ln10
        : null;
    return snapshot;
  }

  void _clearCollection() {
    _count = _clipped = 0;
    _powers.clear();
  }

  void _clearMeter([String state = 'unavailable']) {
    _speechFrames = 0;
    _meterState = state;
    _meterDbfs = null;
  }

  void _finishCollection() {
    _powers.sort();
    final n = _powers.length;
    if (_clipped >= 50) {
      _reason = 'clipping';
    } else if (n < 400) {
      _reason = 'insufficient_samples';
    } else if (10 *
            math.log(_powers[(n * .75).floor()] / _powers[(n * .25).floor()]) /
            math.ln10 >
        12 + 1e-9) {
      _reason = 'unstable_environment';
    } else {
      final lower = _powers[(n - 1) ~/ 2], upper = _powers[n ~/ 2];
      _noiseDbfs = 10 * math.log(lower + (upper - lower) / 2) / math.ln10;
      _offset = (((_noiseDbfs! + 60) / 10).clamp(0.0, 3.0) * 10).round() / 10;
    }
    _state = _reason == null ? 'ready' : 'failed';
    _powers.clear();
  }
}
