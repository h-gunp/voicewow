const prosodyCleanupMessage = 'voicemate:prosody:cleanup';
const prosodyExitMessage = 'voicemate:prosody:exit';

Uri embeddedProsodyUri(Uri base) =>
    base.resolve('prosody/index.html?embedded=1');

bool acceptsProsodyExit({
  required String origin,
  required String expectedOrigin,
  required bool fromFrame,
  required Object? data,
}) =>
    origin == expectedOrigin &&
    fromFrame &&
    data is Map &&
    data['type'] == prosodyExitMessage;

/// The browser adapter is separate so microphone teardown can be tested without
/// starting a real recorder or depending on an embedded document being loaded.
abstract interface class ProsodyFramePort {
  void postCleanup();
  void stopSameOriginAudio();
  void remove();
}

class ProsodyFrameLifecycle {
  ProsodyFrameLifecycle(this._port);
  final ProsodyFramePort _port;
  bool _disposed = false;

  void stopAudio() {
    if (_disposed) return;
    try {
      _port.postCleanup();
    } catch (_) {
      // Continue even when the document has already unloaded.
    }
    try {
      // postMessage is queued. Stop tracks synchronously before removing the
      // iframe, which otherwise might discard that queued cleanup message.
      _port.stopSameOriginAudio();
    } catch (_) {
      // A loading/navigating document may not expose its cleanup hook yet.
    }
  }

  void dispose() {
    if (_disposed) return;
    stopAudio();
    _disposed = true;
    _port.remove();
  }
}
