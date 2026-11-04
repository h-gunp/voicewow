import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'speech_transport.dart';
import '../../../shared/native_tts_coordinator.dart';

SpeechTransport createSpeechTransport() => NativeSpeechTransport();

/// Android callbacks from flutter_tts omit utterance IDs. Keep an issued
/// utterance until its terminal event drains before issuing a newer one.
class NativeSpeechTransport implements SpeechTransport {
  final Duration cancellationTimeout;
  FlutterTts? _tts;
  NativeTtsLease? _lease;
  SpeechTransportListener? _listener;
  _NativeUtterance? _issued;
  _NativeAttempt? _attempt;
  Future<void> _operations = Future.value();
  bool _disposed = false;

  NativeSpeechTransport({
    this.cancellationTimeout = const Duration(seconds: 1),
  });

  @override
  set onEvent(SpeechTransportListener? listener) => _listener = listener;

  void _installCallbacks(NativeTtsLease lease, FlutterTts tts) {
    NativeTtsCoordinator.shared.installHandler(lease, (call) async {
      if (call.method.startsWith('speak.')) {
        await tts.platformCallHandler(call);
      }
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
      NativeTtsLease? lease;
      try {
        lease = await NativeTtsCoordinator.shared.acquire(
          NativeTtsKind.speech,
          timeout: cancellationTimeout,
          cancelled: attempt.cancelled.future,
        );
        if (lease == null || !_current(attempt)) {
          result.complete(false);
          return;
        }
        _lease = lease;
        final tts = _tts = FlutterTts();
        tts.setStartHandler(_onStart);
        tts.setContinueHandler(_onStart);
        tts.setCompletionHandler(
          () => _terminal(SpeechTransportEventType.completed),
        );
        tts.setCancelHandler(
          () => _terminal(SpeechTransportEventType.cancelled),
        );
        tts.setErrorHandler((_) => _terminal(SpeechTransportEventType.error));
        _installCallbacks(lease, tts);
        final available = await tts.isLanguageAvailable('ko-KR');
        if (!_current(attempt) || available != true) {
          result.complete(false);
          return;
        }
        final language = await tts.setLanguage('ko-KR');
        if (!_current(attempt) || language == 0) {
          result.complete(false);
          return;
        }
        await tts.setSpeechRate(slow ? 0.3 : 0.48);
        if (!_current(attempt)) {
          result.complete(false);
          return;
        }
        await tts.setPitch(1);
        if (!_current(attempt)) {
          result.complete(false);
          return;
        }
        final utterance = _NativeUtterance(requestId);
        _issued = utterance;
        lease.issued = true;
        final acknowledged = await tts.speak(text);
        if (acknowledged != null && acknowledged != 1) {
          lease.rejectIssue();
          if (identical(_issued, utterance)) {
            _issued = null;
            utterance.terminal.complete();
          }
          result.complete(false);
        } else {
          result.complete(true);
        }
      } catch (_) {
        if (_issued?.id == requestId) {
          _issued!.retired = true;
          _issued!.silent = true;
          unawaited(_cancelEngine());
        }
        if (!result.isCompleted) result.complete(false);
      } finally {
        lease?.releaseUnissued();
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
    if (!_disposed && !utterance.silent) {
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
      final lease = _lease;
      final tts = _tts;
      if (lease != null && lease.isCurrent && lease.issued && tts != null) {
        await tts.stop();
      }
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
  bool silent = false;
  _NativeUtterance(this.id);
}
