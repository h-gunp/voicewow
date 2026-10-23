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
  int frameCount = 0, _epoch = 0;
  bool _acceptEvents = false, _disposed = false;
  SessionController(this._audio) {
    _subscription = _audio.events.listen(_onEvent);
  }
  bool get active =>
      state == CaptureState.requesting || state == CaptureState.running;

  double? get displayLevel {
    if (level == null) return null;
    if (level!.dbfs == null) return 0;
    // 표시 척도를 이동하는 고정값이며 실제 음압 보정값은 아니다.
    return (level!.dbfs! + inputLevelOffset).clamp(0.0, 120.0).toDouble();
  }

  void selectScenario(Scenario value) {
    if (active || _disposed) return;
    scenario = value;
    reason = null;
    notifyListeners();
  }

  Future<void> start() async {
    if (scenario == null || active || _disposed) return;
    final epoch = ++_epoch;
    _acceptEvents = true;
    state = CaptureState.requesting;
    level = null;
    reason = null;
    settings = {};
    frameCount = 0;
    notifyListeners();
    try {
      await _audio.start();
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
    notifyListeners();
    await _audio.stop();
  }

  void _onEvent(AudioEvent event) {
    if (_disposed || !_acceptEvents) return;
    switch (event.type) {
      case 'state':
        state = event.state!;
        reason = event.reason;
        if (state != CaptureState.running) level = null;
        if (state == CaptureState.idle || state == CaptureState.error)
          _acceptEvents = false;
      case 'level':
        if (state != CaptureState.running) return;
        level = event;
        frameCount++;
      case 'settings':
        settings = event.settings!;
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
