import 'dart:async';
import 'dart:js_interop';
import 'speech_transport.dart';

SpeechTransport createSpeechTransport({bool localOnly = false}) =>
    WebSpeechTransport(localOnly: localOnly);

/// One utterance per request preserves callback identity. Unconditional browser
/// cancel also removes utterances queued before their first start callback.
class WebSpeechTransport implements SpeechTransport {
  WebSpeechTransport({this.localOnly = false});

  final bool localOnly;
  SpeechTransportListener? _listener;
  _WebRequest? _current;
  bool _disposed = false;

  @override
  set onEvent(SpeechTransportListener? listener) => _listener = listener;

  @override
  Future<bool> speak(
    String text, {
    required int requestId,
    bool slow = false,
  }) async {
    if (_disposed) return false;
    _cancelCurrent();
    final request = _WebRequest(requestId);
    _current = request;
    try {
      final synth = _speechSynthesis;
      if (synth == null) return false;
      var voices = synth.getVoices().toDart;
      if (voices.isEmpty) {
        final changed = Completer<void>();
        final callback = ((JSAny? _) {
          if (!changed.isCompleted) changed.complete();
        }).toJS;
        synth.addEventListener('voiceschanged', callback);
        try {
          voices = synth.getVoices().toDart;
          if (voices.isEmpty) {
            await Future.any([changed.future, request.cancelled.future]);
          }
          voices = synth.getVoices().toDart;
        } finally {
          synth.removeEventListener('voiceschanged', callback);
        }
      }
      if (!_isCurrent(request)) return false;
      final korean = voices.where(
        (voice) =>
            voice.lang.toLowerCase().split('-').first == 'ko' &&
            (!localOnly || voice.localService == true),
      );
      if (korean.isEmpty) return false;
      final utterance = _SpeechUtterance(text);
      request.utterance = utterance;
      utterance.lang = 'ko-KR';
      utterance.voice = korean.first;
      utterance.rate = slow ? 0.65 : 1.0;
      utterance.pitch = 1.0;
      utterance.onstart = ((JSAny? _) {
        if (_isCurrent(request))
          _emit(request, SpeechTransportEventType.started);
      }).toJS;
      utterance.onend = ((JSAny? _) {
        if (_isCurrent(request)) {
          _current = null;
          _emit(request, SpeechTransportEventType.completed);
        }
      }).toJS;
      utterance.onerror = ((_SpeechError event) {
        if (_isCurrent(request)) {
          _current = null;
          final cancelled =
              event.error == 'canceled' || event.error == 'interrupted';
          _emit(
            request,
            cancelled
                ? SpeechTransportEventType.cancelled
                : SpeechTransportEventType.error,
          );
        }
      }).toJS;
      if (!_isCurrent(request)) return false;
      synth.speak(utterance);
      return true;
    } catch (_) {
      if (_isCurrent(request)) _current = null;
      return false;
    }
  }

  bool _isCurrent(_WebRequest request) =>
      !_disposed &&
      identical(_current, request) &&
      !request.cancelled.isCompleted;

  void _emit(_WebRequest request, SpeechTransportEventType type) =>
      _listener?.call(SpeechTransportEvent(request.id, type));

  @override
  Future<void> stop() async {
    _cancelCurrent();
  }

  void _cancelCurrent() {
    final previous = _current;
    _current = null;
    if (previous != null && !previous.cancelled.isCompleted)
      previous.cancelled.complete();
    try {
      _speechSynthesis?.cancel();
    } catch (_) {
      // Text practice also works in browsers without speech synthesis.
    }
    if (previous != null && !_disposed)
      _emit(previous, SpeechTransportEventType.cancelled);
  }

  @override
  Future<void> dispose() async {
    await stop();
    _disposed = true;
    _listener = null;
  }
}

class _WebRequest {
  final int id;
  final cancelled = Completer<void>();
  _SpeechUtterance? utterance;
  _WebRequest(this.id);
}

@JS('speechSynthesis')
external _SpeechSynthesis? get _speechSynthesis;

extension type _SpeechSynthesis._(JSObject _) implements JSObject {
  external JSArray<_SpeechVoice> getVoices();
  external void speak(_SpeechUtterance utterance);
  external void cancel();
  external void addEventListener(String type, JSFunction callback);
  external void removeEventListener(String type, JSFunction callback);
}
extension type _SpeechVoice._(JSObject _) implements JSObject {
  external String get lang;
  external bool? get localService;
}
@JS('SpeechSynthesisUtterance')
extension type _SpeechUtterance._(JSObject _) implements JSObject {
  external factory _SpeechUtterance(String text);
  external set lang(String value);
  external set voice(_SpeechVoice value);
  external set rate(double value);
  external set pitch(double value);
  external set onstart(JSFunction value);
  external set onend(JSFunction value);
  external set onerror(JSFunction value);
}
extension type _SpeechError._(JSObject _) implements JSObject {
  external String get error;
}
