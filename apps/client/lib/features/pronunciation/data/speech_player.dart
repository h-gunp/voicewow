import 'dart:async';
import 'package:flutter/foundation.dart';
import 'speech_transport.dart';
import 'speech_transport_native.dart'
    if (dart.library.js_interop) 'speech_transport_web.dart';

enum SpeechResult { started, unavailable, cancelled }

enum SpeechPhase { ready, preparing, playing }

@immutable
class SpeechPlaybackState {
  final SpeechPhase phase;
  final int requestId;
  final SpeechResult? result;
  const SpeechPlaybackState({
    this.phase = SpeechPhase.ready,
    this.requestId = 0,
    this.result,
  });
}

abstract interface class SpeechPlayer {
  Future<SpeechResult> speak(String text, {bool slow = false});
  Future<void> stop();
  Future<void> dispose();
}

/// Optional lifecycle capability. A command acknowledgement is not a start.
abstract interface class SpeechPlaybackSource {
  ValueListenable<SpeechPlaybackState> get playback;
}

class DeviceSpeechPlayer implements SpeechPlayer, SpeechPlaybackSource {
  final SpeechTransport _transport;
  final Duration preparationTimeout;
  final _state = ValueNotifier(const SpeechPlaybackState());
  _SpeechRequest? _active;
  bool _disposed = false;
  int _nextId = 0;

  DeviceSpeechPlayer({
    this.preparationTimeout = const Duration(seconds: 10),
    SpeechTransport? transport,
  }) : _transport = transport ?? createSpeechTransport() {
    _transport.onEvent = _onEvent;
  }

  @override
  ValueListenable<SpeechPlaybackState> get playback => _state;

  @override
  Future<SpeechResult> speak(String text, {bool slow = false}) {
    if (_disposed) return Future.value(SpeechResult.cancelled);
    if (text.trim().isEmpty) return Future.value(SpeechResult.unavailable);
    if (_active != null) unawaited(stop());
    final request = _SpeechRequest(++_nextId);
    _active = request;
    _state.value = SpeechPlaybackState(
      phase: SpeechPhase.preparing,
      requestId: request.id,
    );
    // Error watchdog only: actual platform callbacks alone enter playing.
    request.watchdog = Timer(preparationTimeout, () {
      if (identical(_active, request)) {
        unawaited(_stopTransport());
        _finish(request, SpeechResult.unavailable);
      }
    });
    unawaited(_begin(request, text, slow));
    return request.started.future;
  }

  Future<void> _begin(_SpeechRequest request, String text, bool slow) async {
    try {
      final accepted = await _transport.speak(
        text,
        requestId: request.id,
        slow: slow,
      );
      if (!_disposed && identical(_active, request) && !accepted) {
        unawaited(_stopTransport());
        _finish(request, SpeechResult.unavailable);
      }
    } catch (_) {
      if (!_disposed && identical(_active, request)) {
        unawaited(_stopTransport());
        _finish(request, SpeechResult.unavailable);
      }
    }
  }

  void _onEvent(SpeechTransportEvent event) {
    final request = _active;
    if (_disposed || request == null || request.id != event.requestId) return;
    switch (event.type) {
      case SpeechTransportEventType.started:
        request.watchdog?.cancel();
        _state.value = SpeechPlaybackState(
          phase: SpeechPhase.playing,
          requestId: request.id,
          result: SpeechResult.started,
        );
        if (!request.started.isCompleted)
          request.started.complete(SpeechResult.started);
      case SpeechTransportEventType.completed:
        _finish(request, null);
      case SpeechTransportEventType.cancelled:
        _finish(request, SpeechResult.cancelled);
      case SpeechTransportEventType.error:
        _finish(request, SpeechResult.unavailable);
    }
  }

  void _finish(_SpeechRequest request, SpeechResult? result) {
    if (!identical(_active, request)) return;
    _active = null;
    request.watchdog?.cancel();
    if (!request.started.isCompleted)
      request.started.complete(result ?? SpeechResult.cancelled);
    _state.value = SpeechPlaybackState(requestId: request.id, result: result);
  }

  Future<void> _stopTransport() async {
    try {
      await _transport.stop();
    } catch (_) {
      // A failed engine stop must not lock text-only practice controls.
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    final request = _active;
    if (request != null) _finish(request, SpeechResult.cancelled);
    await _stopTransport();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    final request = _active;
    if (request != null) _finish(request, SpeechResult.cancelled);
    _disposed = true;
    _transport.onEvent = null;
    try {
      await _transport.dispose();
    } catch (_) {
      // There is no remaining UI to report an engine shutdown error to.
    }
    _state.dispose();
  }
}

class _SpeechRequest {
  final int id;
  final started = Completer<SpeechResult>();
  Timer? watchdog;
  _SpeechRequest(this.id);
}
