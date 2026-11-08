import 'dart:async';
import 'package:flutter/foundation.dart';
import 'audio/audio_port.dart';
import 'scenario.dart';

class SessionController extends ChangeNotifier {
  static const double inputLevelOffset = 114;

  final AudioPort _audio;
  final double levelOffset;
  late final StreamSubscription<AudioEvent> _subscription;
  Scenario? scenario;
  CaptureState state = CaptureState.idle;
  AudioEvent? level;
  String? reason;
  Map<String, Object?> settings = {};
  Map<String, Object?> analysis = {};
  bool noiseReductionEnabled = true;
  int frameCount = 0, _epoch = 0;
  int _environmentRequest = 0;
  bool _cancellingEnvironment = false;
  bool _acceptEvents = false, _disposed = false;
  SessionController(this._audio, {this.levelOffset = inputLevelOffset}) {
    _subscription = _audio.events.listen(_onEvent);
  }
  bool get active =>
      state == CaptureState.requesting || state == CaptureState.running;

  String? get _processingProvenance {
    const keys = ['autoGainControl', 'noiseSuppression', 'echoCancellation'];
    if (keys.any(
      (key) => settings.containsKey(key) && settings[key] != false,
    )) {
      return null;
    }
    return keys.every(settings.containsKey) ? 'verified' : 'relative_input';
  }

  bool get environmentCollecting => analysis['state'] == 'collecting';
  bool get canSampleEnvironment =>
      !_disposed &&
      !_cancellingEnvironment &&
      state == CaptureState.running &&
      noiseReductionEnabled &&
      settings['noiseReductionState'] == 'active' &&
      settings['vadStatus'] == 'ready' &&
      analysis['reason'] != 'vad_runtime_failed' &&
      _processingProvenance != null &&
      !environmentCollecting;
  bool get canCancelEnvironment =>
      !_disposed && environmentCollecting && !_cancellingEnvironment;
  double get environmentProgress {
    final value = analysis['progress'];
    return value is num && value.isFinite
        ? value.clamp(0.0, 1.0).toDouble()
        : 0.0;
  }

  ({double lower, double upper, bool adjusted}) get effectiveRange {
    final s = scenario!;
    final value = analysis['offset'];
    final valid =
        state == CaptureState.running &&
        analysis['calibrationValid'] == true &&
        _processingProvenance != null &&
        analysis['provenance'] == _processingProvenance &&
        value is num &&
        value.isFinite &&
        value >= 0 &&
        value <= 3;
    final offset = valid ? value.toDouble() : 0.0;
    return (
      lower: double.parse(
        (s.referenceLower + offset).clamp(0.0, 120.0).toStringAsFixed(1),
      ),
      upper: double.parse(
        (s.referenceUpper + offset).clamp(0.0, 120.0).toStringAsFixed(1),
      ),
      adjusted: valid,
    );
  }

  double? get displayLevel {
    if (state != CaptureState.running ||
        environmentCollecting ||
        analysis['meterState'] != 'speech' ||
        analysis['speech'] != 'speech')
      return null;
    final dbfs = analysis['meterDbfs'];
    if (dbfs is! num || !dbfs.isFinite) return null;
    // 플랫폼별 표시 보정값은 실제 기기에서 확인한 사용자 설정을 사용한다.
    return (dbfs + levelOffset).clamp(0.0, 120.0).toDouble();
  }

  void selectScenario(Scenario value) {
    if (active || _disposed) return;
    scenario = value;
    reason = null;
    notifyListeners();
  }

  Future<void> sampleEnvironment() async {
    if (!canSampleEnvironment) return;
    final epoch = _epoch;
    final request = ++_environmentRequest;
    analysis = {
      ...analysis,
      'state': 'collecting',
      'progress': 0.0,
      'reason': null,
      'meterState': 'calibrating',
      'meterDbfs': null,
    };
    notifyListeners();
    try {
      await _audio.sampleEnvironment();
    } catch (_) {
      if (!_disposed &&
          epoch == _epoch &&
          request == _environmentRequest &&
          environmentCollecting) {
        analysis = {
          ...analysis,
          'state': 'failed',
          'reason': 'sample_failed',
          'meterState': 'unavailable',
          'meterDbfs': null,
        };
        notifyListeners();
      }
    }
  }

  Future<void> cancelEnvironment() async {
    if (!canCancelEnvironment) return;
    final epoch = _epoch;
    final request = ++_environmentRequest;
    _cancellingEnvironment = true;
    notifyListeners();
    try {
      await _audio.cancelEnvironment();
      if (!_disposed &&
          epoch == _epoch &&
          request == _environmentRequest &&
          environmentCollecting) {
        analysis = {
          ...analysis,
          'state': analysis['calibrationValid'] == true ? 'ready' : 'idle',
          'reason': 'cancelled',
          'progress': 0.0,
          'meterState': 'unavailable',
          'meterDbfs': null,
        };
      }
    } catch (_) {
      if (!_disposed &&
          epoch == _epoch &&
          request == _environmentRequest &&
          environmentCollecting) {
        analysis = {...analysis, 'reason': 'cancel_failed'};
      }
    } finally {
      if (!_disposed && epoch == _epoch && request == _environmentRequest) {
        _cancellingEnvironment = false;
        notifyListeners();
      }
    }
  }

  Future<void> setNoiseReductionEnabled(bool value) async {
    if (_disposed ||
        state == CaptureState.requesting ||
        noiseReductionEnabled == value)
      return;
    noiseReductionEnabled = value;
    if (state == CaptureState.running) {
      final stopping = stop();
      // Start before awaiting close to retain Safari's click activation.
      final starting = start();
      await Future.wait([stopping, starting]);
    } else {
      notifyListeners();
    }
  }

  Future<void> start() async {
    if (scenario == null || active || _disposed) return;
    final epoch = ++_epoch;
    _cancellingEnvironment = false;
    _acceptEvents = true;
    state = CaptureState.requesting;
    level = null;
    reason = null;
    settings = {};
    analysis = {};
    frameCount = 0;
    notifyListeners();
    try {
      await _audio.start(noiseReductionEnabled: noiseReductionEnabled);
    } catch (_) {
      if (!_disposed && epoch == _epoch) {
        state = CaptureState.error;
        reason = 'processing_error';
        _acceptEvents = false;
        level = null;
        notifyListeners();
      }
    }
  }

  Future<void> stop() async {
    if (_disposed) return;
    ++_epoch;
    _cancellingEnvironment = false;
    _acceptEvents = false;
    state = CaptureState.idle;
    level = null;
    reason = null;
    analysis = {};
    notifyListeners();
    await _audio.stop();
  }

  void _onEvent(AudioEvent event) {
    if (_disposed || !_acceptEvents) return;
    switch (event.type) {
      case 'state':
        state = event.state!;
        reason = event.reason;
        if (state != CaptureState.running) {
          level = null;
          analysis = {};
        }
        if (state == CaptureState.idle || state == CaptureState.error) {
          _acceptEvents = false;
        }
      case 'level':
        if (state != CaptureState.running) return;
        level = event;
        frameCount++;
      case 'settings':
        ++_environmentRequest;
        _cancellingEnvironment = false;
        settings = event.settings!;
        analysis = {};
      case 'analysis':
        if (state != CaptureState.running) return;
        analysis = event.analysis!;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _acceptEvents = false;
    ++_epoch;
    unawaited(_subscription.cancel());
    unawaited(_audio.dispose());
    super.dispose();
  }
}
