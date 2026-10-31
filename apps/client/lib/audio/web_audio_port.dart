import 'dart:async';
import 'dart:js_interop';
import 'audio_port.dart';

@JS('voiceMateAudio')
external _AudioApi? get _audioApi;
extension type _AudioApi(JSObject _) implements JSObject {
  external _Capture createCapture(_Options options);
}
extension type _Options._(JSObject _) implements JSObject {
  external factory _Options({JSFunction onEvent});
}
extension type _Capture(JSObject _) implements JSObject {
  external JSPromise<JSAny?> start(JSBoolean noiseReductionEnabled);
  external JSPromise<JSAny?> stop();
}

AudioPort createAudioPort() => WebAudioPort();

class WebAudioPort implements AudioPort {
  final _events = StreamController<AudioEvent>.broadcast(sync: true);
  _Capture? _capture;
  bool _disposed = false;
  WebAudioPort() {
    _capture = _audioApi?.createCapture(
      _Options(
        onEvent: ((JSAny? raw) {
          if (_disposed) return;
          final decoded = raw.dartify();
          if (decoded is! Map) return;
          switch (decoded['type']) {
            case 'state':
              final name = decoded['state'];
              final state = CaptureState.values
                  .where((s) => s.name == name)
                  .firstOrNull;
              if (state != null)
                _events.add(
                  AudioEvent.state(state, reason: decoded['reason'] as String?),
                );
            case 'level':
              _events.add(
                AudioEvent.level(
                  rms: (decoded['rms'] as num).toDouble(),
                  peak: (decoded['peak'] as num?)?.toDouble(),
                  dbfs: (decoded['dbfs'] as num?)?.toDouble(),
                  normalized: (decoded['normalized'] as num).toDouble(),
                  sampleCount: (decoded['sampleCount'] as num).toInt(),
                ),
              );
            case 'settings':
              _events.add(
                AudioEvent.settings(
                  Map<String, Object?>.from(decoded['settings'] as Map),
                ),
              );
            case 'analysis':
              if (decoded['analysis'] is Map) {
                _events.add(
                  AudioEvent.analysis(
                    Map<String, Object?>.from(decoded['analysis'] as Map),
                  ),
                );
              }
          }
        }).toJS,
      ),
    );
  }
  @override
  Stream<AudioEvent> get events => _events.stream;
  @override
  Future<void> start({bool noiseReductionEnabled = true}) async {
    if (_capture == null) {
      _events.add(
        const AudioEvent.state(CaptureState.error, reason: 'unsupported'),
      );
      return;
    }
    await _capture!.start(noiseReductionEnabled.toJS).toDart;
  }

  @override
  Future<void> stop() async {
    await _capture?.stop().toDart;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await stop();
    await _events.close();
  }
}
