enum CaptureState { idle, requesting, running, error }

class AudioEvent {
  final String type;
  final CaptureState? state;
  final String? reason;
  final double? rms, peak, dbfs, normalized;
  final int? sampleCount;
  final Map<String, Object?>? settings;
  final Map<String, Object?>? analysis;
  const AudioEvent.state(this.state, {this.reason})
    : type = 'state',
      rms = null,
      peak = null,
      dbfs = null,
      normalized = null,
      sampleCount = null,
      settings = null,
      analysis = null;
  const AudioEvent.level({
    required this.rms,
    this.peak,
    required this.dbfs,
    required this.normalized,
    required this.sampleCount,
  }) : type = 'level',
       state = null,
       reason = null,
       settings = null,
       analysis = null;
  const AudioEvent.settings(this.settings)
    : type = 'settings',
      state = null,
      reason = null,
      rms = null,
      peak = null,
      dbfs = null,
      normalized = null,
      sampleCount = null,
      analysis = null;
  const AudioEvent.analysis(this.analysis)
    : type = 'analysis',
      state = null,
      reason = null,
      rms = null,
      peak = null,
      dbfs = null,
      normalized = null,
      sampleCount = null,
      settings = null;
}

abstract interface class AudioPort {
  Stream<AudioEvent> get events;
  Future<void> start({bool noiseReductionEnabled = true});
  Future<void> stop();
  Future<void> dispose();
}
