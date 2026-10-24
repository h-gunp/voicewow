import 'dart:async';
import 'package:voicemate/audio/audio_port.dart';

class FakeAudioPort implements AudioPort {
  final controller = StreamController<AudioEvent>.broadcast(sync: true);
  int starts = 0, stops = 0;
  Completer<void>? gate;
  Completer<void>? stopGate;
  @override
  Stream<AudioEvent> get events => controller.stream;
  void send(AudioEvent event) => controller.add(event);
  @override
  Future<void> start() async {
    starts++;
    if (gate != null) await gate!.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (stopGate != null) await stopGate!.future;
  }

  @override
  Future<void> dispose() async {
    await controller.close();
  }
}
