import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'speech_transport.dart';

SpeechTransport createSpeechTransport() => NativeSpeechTransport();

/// Android callbacks from flutter_tts omit utterance IDs. Keep an issued
/// utterance until its terminal event drains before issuing a newer one.
class NativeSpeechTransport implements SpeechTransport {
  final Duration cancellationTimeout;
  final FlutterTts _tts = FlutterTts();
  static const _channel = MethodChannel('flutter_tts');
  SpeechTransportListener? _listener;
  _NativeUtterance? _issued;
  _NativeAttempt? _attempt;
  Future<void> _operations = Future.value();
  bool _disposed = false;

  NativeSpeechTransport({
    this.cancellationTimeout = const Duration(seconds: 1),
  }) {
    _tts.setStartHandler(_onStart);
    _tts.setContinueHandler(_onStart);
    _tts.setCompletionHandler(
      () => _terminal(SpeechTransportEventType.completed),
    );
    _tts.setCancelHandler(() => _terminal(SpeechTransportEventType.cancelled));
    _tts.setErrorHandler((_) => _terminal(SpeechTransportEventType.error));
  }

  @override
  set onEvent(SpeechTransportListener? listener) => _listener = listener;

  void _claimCallbacks() {
    // Another feature's FlutterTts constructor replaces this global handler.
    // Reclaim for each playback and ignore file-synthesis lifecycle events.
    _channel.setMethodCallHandler((call) async {
      if (call.method.startsWith('speak.'))
        await _tts.platformCallHandler(call);
    });
  }

  @override
  Future<bool> speak(String text, {required int requestId, bool slow = false}) {
    if (_disposed) return Future.value(false);
    _attempt?.cancel();
    final attempt = _NativeAttempt(requestId);
    _attempt = attempt;
    final result = Completer<bool>();
    _operations = _operations.then((_) async {
      try {
        _claimCallbacks();
        final issued = _issued;
        if (issued != null) {
          await Future.any([issued.terminal.future, attempt.cancelled.future]);
        }
        if (!_current(attempt)) {
          result.complete(false);
          return;
        }
        _claimCallbacks();
        final available = await _tts.isLanguageAvailable('ko-KR');
        if (!_current(attempt) || available != true) {
          result.complete(false);
          return;
        }
        final language = await _tts.setLanguage('ko-KR');
        if (!_current(attempt) || language == 0) {
          result.complete(false);
          return;
        }
        await _tts.setSpeechRate(slow ? 0.3 : 0.48);
        if (!_current(attempt)) {
          result.complete(false);
          return;
        }
        await _tts.setPitch(1);
        if (!_current(attempt)) {
          result.complete(false);
          return;
        }
        _claimCallbacks();
        final utterance = _NativeUtterance(requestId);
        _issued = utterance;
        final acknowledged = await _tts.speak(text);
        if (acknowledged != null && acknowledged != 1) {
          if (identical(_issued, utterance))
            _terminal(SpeechTransportEventType.error);
          result.complete(false);
        } else {
          result.complete(true);
        }
      } catch (_) {
        if (_current(attempt) && _issued?.id == requestId) {
          _terminal(SpeechTransportEventType.error);
        }
        if (!result.isCompleted) result.complete(false);
      }
    });
    return result.future;
  }

  bool _current(_NativeAttempt attempt) =>
      !_disposed &&
      identical(_attempt, attempt) &&
      !attempt.cancelled.isCompleted;

  void _onStart() {
    final utterance = _issued;
    if (utterance == null) return;
    if (_disposed || utterance.retired) {
      unawaited(_cancelEngine());
      return;
    }
    _listener?.call(
      SpeechTransportEvent(utterance.id, SpeechTransportEventType.started),
    );
  }

  void _terminal(SpeechTransportEventType type) {
    final utterance = _issued;
    if (utterance == null) return;
    _issued = null;
    if (!utterance.terminal.isCompleted) utterance.terminal.complete();
    if (!_disposed) {
      _listener?.call(
        SpeechTransportEvent(
          utterance.id,
          utterance.retired ? SpeechTransportEventType.cancelled : type,
        ),
      );
    }
  }

  Future<void> _cancelEngine() async {
    try {
      _claimCallbacks();
      await _tts.stop();
    } catch (_) {
      // Keep a retired request quarantined until its terminal event arrives.
    }
  }

  @override
  Future<void> stop() async {
    _attempt?.cancel();
    _attempt = null;
    final utterance = _issued;
    if (utterance == null) return;
    utterance.retired = true;
    try {
      await Future.wait<void>([
        _cancelEngine(),
        utterance.terminal.future,
      ]).timeout(cancellationTimeout);
    } on TimeoutException {
      // A normal section transition waits for the cancel event before another
      // FlutterTts client can replace our channel handler. If an engine omits
      // it, keep quarantine rather than assigning stale events to a new voice.
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    _listener = null;
  }
}

class _NativeAttempt {
  final int id;
  final cancelled = Completer<void>();
  _NativeAttempt(this.id);
  void cancel() {
    if (!cancelled.isCompleted) cancelled.complete();
  }
}

class _NativeUtterance {
  final int id;
  final terminal = Completer<void>();
  bool retired = false;
  _NativeUtterance(this.id);
}
