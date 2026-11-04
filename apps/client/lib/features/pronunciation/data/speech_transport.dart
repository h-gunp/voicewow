enum SpeechTransportEventType { started, completed, cancelled, error }

class SpeechTransportEvent {
  final int requestId;
  final SpeechTransportEventType type;
  const SpeechTransportEvent(this.requestId, this.type);
}

typedef SpeechTransportListener = void Function(SpeechTransportEvent event);

/// A true speak return acknowledges a queued command; only a start event
/// confirms that audible playback has actually started.
abstract interface class SpeechTransport {
  set onEvent(SpeechTransportListener? listener);
  Future<bool> speak(String text, {required int requestId, bool slow = false});
  Future<void> stop();
  Future<void> dispose();
}
