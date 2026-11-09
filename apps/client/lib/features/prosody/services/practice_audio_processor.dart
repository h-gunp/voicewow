import 'package:flutter/services.dart';

class ProcessedAudioChunk {
  const ProcessedAudioChunk(this.samples, this.speech);
  final List<double> samples;
  final List<int> speech;
}

/// One independent audio/VAD state. Cancellation never reuses its native id.
class NativePracticeAudioSession {
  static const _channel = MethodChannel('voicemate/practice_audio');
  static int _nextId = 0;
  final int _id = ++_nextId;
  int _sequence = 0,
      _inputSamples = 0,
      _outputSamples = 0,
      _decisions = 0,
      _sentBytes = 0;
  bool _cancelled = false, _voiceActivityEnabled = true;
  double rawVariance = 0;
  Future<void>? _cancel;

  Future<T> _bounded<T>(Future<T> operation) => operation.timeout(
    const Duration(seconds: 3),
    onTimeout: () => throw PlatformException(
      code: 'audio_processing_timeout',
      message: '음성 처리가 응답하지 않아요. 다시 녹음해 주세요.',
    ),
  );

  Future<void> create({
    bool noiseReductionEnabled = true,
    bool voiceActivityEnabled = true,
  }) async {
    _voiceActivityEnabled = voiceActivityEnabled;
    final result = await _bounded(
      _channel.invokeMapMethod<Object?, Object?>('create', {
        'session': _id,
        'noiseReductionEnabled': noiseReductionEnabled,
        'voiceActivityEnabled': voiceActivityEnabled,
      }),
    );
    if (result?['inputSampleRate'] != 48000 || result?['sampleRate'] != 16000) {
      throw StateError('Unexpected practice audio format');
    }
  }

  Future<ProcessedAudioChunk> process(Uint8List pcm) async {
    if (_cancelled) throw StateError('Audio processing cancelled');
    _sentBytes += pcm.length;
    return _read(
      await _bounded(
        _channel.invokeMapMethod<Object?, Object?>('process', {
          'session': _id,
          'sequence': _sequence++,
          'pcm': pcm,
        }),
      ),
    );
  }

  Future<ProcessedAudioChunk> finish() async {
    if (_cancelled) throw StateError('Audio processing cancelled');
    final result = _read(
      await _bounded(
        _channel.invokeMapMethod<Object?, Object?>('finish', {'session': _id}),
      ),
    );
    if (_outputSamples != (_inputSamples + 2) ~/ 3 ||
        (_voiceActivityEnabled &&
            _decisions != (_outputSamples + 159) ~/ 160)) {
      throw StateError('Incomplete processed recording');
    }
    return result;
  }

  ProcessedAudioChunk _read(Map<Object?, Object?>? result) {
    if (_cancelled || result == null) {
      throw StateError('Audio processing cancelled');
    }
    final raw = result['samples'], decisions = result['speech'];
    final input = result['inputSamples'], output = result['outputSamples'];
    final variance = result['rawVariance'];
    if (raw is! List ||
        decisions is! List ||
        input is! int ||
        output is! int ||
        variance is! num ||
        !variance.isFinite ||
        variance < 0 ||
        variance > 1) {
      throw StateError('Invalid processed audio response');
    }
    final samples = raw.map((value) => (value as num).toDouble()).toList();
    final speech = decisions.cast<int>().toList();
    if (samples.any((value) => !value.isFinite || value.abs() > 1) ||
        speech.any((value) => value < 0 || value > 2) ||
        input < _inputSamples ||
        input != _sentBytes ~/ 2 ||
        input > 48000 * 20 ||
        output != _outputSamples + samples.length ||
        output > (input + 2) ~/ 3 ||
        (_voiceActivityEnabled
            ? _decisions + speech.length > (input + 479) ~/ 480 ||
                  output > (_decisions + speech.length) * 160
            : speech.isNotEmpty) ||
        output > 16000 * 20) {
      throw StateError('Invalid processed audio sequence');
    }
    _inputSamples = input;
    _outputSamples = output;
    _decisions += speech.length;
    rawVariance = variance.toDouble();
    return ProcessedAudioChunk(samples, speech);
  }

  Future<void> cancel() {
    _cancelled = true;
    return _cancel ??= _bounded(
      _channel.invokeMethod<void>('cancel', {'session': _id}),
    );
  }
}
