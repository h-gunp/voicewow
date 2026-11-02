import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';

enum SpeechResult { started, unavailable, cancelled }

abstract interface class SpeechPlayer {
  Future<SpeechResult> speak(String text, {bool slow = false});
  Future<void> stop();
  Future<void> dispose();
}

class DeviceSpeechPlayer implements SpeechPlayer {
  final FlutterTts _tts = FlutterTts();
  bool _disposed = false;
  int _epoch = 0;
  Completer<SpeechResult>? _pending;

  DeviceSpeechPlayer() {
    _tts.setStartHandler(() {
      final pending = _pending;
      if (pending != null && !pending.isCompleted) {
        pending.complete(SpeechResult.started);
      }
    });
    _tts.setErrorHandler((_) {
      final pending = _pending;
      if (pending != null && !pending.isCompleted) {
        pending.complete(SpeechResult.unavailable);
      }
    });
  }

  void _cancelPending() {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.complete(SpeechResult.cancelled);
    }
    _pending = null;
  }

  @override
  Future<SpeechResult> speak(String text, {bool slow = false}) async {
    final epoch = ++_epoch;
    _cancelPending();
    try {
      await _tts.stop();
      final available = await _tts.isLanguageAvailable('ko-KR');
      if (_disposed || epoch != _epoch) return SpeechResult.cancelled;
      if (available != true) return SpeechResult.unavailable;
      await _tts.setLanguage('ko-KR');
      await _tts.setSpeechRate(slow ? 0.3 : 0.48);
      await _tts.setPitch(1);
      if (_disposed || epoch != _epoch) return SpeechResult.cancelled;
      final pending = Completer<SpeechResult>();
      _pending = pending;
      final result = await _tts.speak(text);
      if (_disposed || epoch != _epoch) return SpeechResult.cancelled;
      // Android returns 1; flutter_tts Web returns null on a successful call.
      // On Web, confirm the actual start callback instead of treating null as
      // a voice failure (or assuming that it means successful playback).
      if (result == 1 && !pending.isCompleted) {
        pending.complete(SpeechResult.started);
      } else if (result != null && result != 1 && !pending.isCompleted) {
        pending.complete(SpeechResult.unavailable);
      }
      final outcome = await pending.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () => SpeechResult.unavailable,
      );
      if (identical(_pending, pending)) _pending = null;
      return outcome;
    } catch (_) {
      return _disposed || epoch != _epoch
          ? SpeechResult.cancelled
          : SpeechResult.unavailable;
    }
  }

  @override
  Future<void> stop() async {
    ++_epoch;
    _cancelPending();
    try {
      await _tts.stop();
    } catch (_) {
      // Text guidance is available even without a device voice.
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await stop();
  }
}
