import 'dart:async';
import 'audio_port.dart';

AudioPort createAudioPort() => UnsupportedAudioPort();

class UnsupportedAudioPort implements AudioPort {
  final _events = StreamController<AudioEvent>.broadcast(sync: true);
  @override
  Stream<AudioEvent> get events => _events.stream;
  @override
  Future<void> start({bool noiseReductionEnabled = true}) async => _events.add(
    const AudioEvent.state(CaptureState.error, reason: 'unsupported'),
  );
  @override
  Future<void> stop() async {}
  @override
  Future<void> beginSpeakerEnrollment() async =>
      _events.add(const AudioEvent.speaker({'state': 'unavailable'}));
  @override
  Future<void> deleteSpeaker() async {}
  @override
  Future<void> dispose() async => _events.close();
}
