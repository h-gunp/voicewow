import 'dart:async';
import 'package:flutter/foundation.dart';
import 'audio/audio_port.dart';
import 'scenario.dart';

class SessionController extends ChangeNotifier {
  static const double inputLevelOffset = 114;

  final AudioPort _audio;
  late final StreamSubscription<AudioEvent> _subscription;
  Scenario? scenario;
  CaptureState state = CaptureState.idle;
  AudioEvent? level;
  String? reason;
  Map<String, Object?> settings = {};
  Map<String, Object?> analysis = {};
  Map<String, Object?> speaker = {'state': 'unregistered'};
  bool speakerRegistered = false;
  bool noiseReductionEnabled = true;
  int frameCount = 0, _epoch = 0;
  bool _acceptEvents = false, _disposed = false;
  SessionController(this._audio) {
    _subscription = _audio.events.listen(_onEvent);
  }
  bool get active =>
      state == CaptureState.requesting || state == CaptureState.running;

  ({double lower, double upper, bool adjusted}) get effectiveRange {
    final s = scenario!;
    final value = analysis['offset'];
    final valid =
        analysis['state'] == 'ready' &&
        [
          'autoGainControl',
          'noiseSuppression',
          'echoCancellation',
        ].every((key) => settings[key] == false) &&
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
        analysis['meterState'] != 'speech' ||
        analysis['speech'] != 'speech')
      return null;
    final dbfs = analysis['meterDbfs'];
    if (dbfs is! num || !dbfs.isFinite) return null;
    // 웹사이트 측정값과 보정 전 값의 차이를 사용자가 실험으로 관측한 보정값이다.
    return (dbfs + inputLevelOffset).clamp(0.0, 120.0).toDouble();
  }

  void selectScenario(Scenario value) {
    if (active || _disposed) return;
    scenario = value;
    reason = null;
    notifyListeners();
  }

  Future<void> beginSpeakerEnrollment() async {
    if (state != CaptureState.running ||
        settings['speakerAvailable'] != true ||
        _disposed)
      return;
    await _audio.beginSpeakerEnrollment();
  }

  Future<void> deleteSpeaker() async {
    if (_disposed) return;
    await _audio.deleteSpeaker();
    speakerRegistered = false;
    speaker = {'state': 'unregistered'};
    notifyListeners();
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
    _acceptEvents = true;
    state = CaptureState.requesting;
    level = null;
    reason = null;
    settings = {};
    analysis = {};
    speaker = {'state': speakerRegistered ? 'confirming' : 'unregistered'};
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
    _acceptEvents = false;
    state = CaptureState.idle;
    level = null;
    reason = null;
    analysis = {};
    speaker = {'state': speakerRegistered ? 'confirming' : 'unregistered'};
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
          speaker = {
            'state': speakerRegistered ? 'confirming' : 'unregistered',
          };
        }
        if (state == CaptureState.idle || state == CaptureState.error)
          _acceptEvents = false;
      case 'level':
        if (state != CaptureState.running) return;
        level = event;
        frameCount++;
      case 'settings':
        settings = event.settings!;
        analysis = {};
      case 'analysis':
        if (state != CaptureState.running) return;
        analysis = event.analysis!;
      case 'speaker':
        speaker = event.analysis!;
        if (speaker['state'] == 'registered') speakerRegistered = true;
        if (speaker['state'] == 'unregistered' ||
            speaker['state'] == 'registering')
          speakerRegistered = false;
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
