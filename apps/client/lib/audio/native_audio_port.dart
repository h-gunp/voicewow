import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:record/record.dart';

import 'audio_port.dart';
import 'native_level_analysis.dart';
import 'unsupported_audio_port.dart' as unsupported;

AudioPort createAudioPort() =>
    Platform.isAndroid ? NativeAudioPort() : unsupported.createAudioPort();

/// The native worker owns PCM and DSP; only level measurements cross the channel.
class NativeAudioPort with WidgetsBindingObserver implements AudioPort {
  NativeAudioPort() {
    _channel.setMethodCallHandler(_onNativeEvent);
    WidgetsBinding.instance.addObserver(this);
  }

  static const _channel = MethodChannel('voicemate/volume');
  static int _nextSession = 0;
  final _events = StreamController<AudioEvent>.broadcast(sync: true);
  AudioRecorder? _permission;
  NativeLevelAnalysis _analysis = NativeLevelAnalysis();
  int? _session, _sampleBoundary;
  final _pendingReleases = <int>{};
  int _lastSequence = -1;
  int _sampleRequest = 0, _missingTicks = 0;
  bool _running = false, _noiseReduction = true, _disposed = false;
  Timer? _watchdog;
  Future<void> _stopping = Future<void>.value();
  Future<void>? _disposing;

  @override
  Stream<AudioEvent> get events => _events.stream;

  bool _current(int session) => !_disposed && _session == session;
  void _emit(AudioEvent event) {
    if (!_disposed) _events.add(event);
  }

  @override
  Future<void> start({bool noiseReductionEnabled = true}) async {
    if (_disposed || _session != null) return;
    final ticket = _session = ++_nextSession;
    _noiseReduction = noiseReductionEnabled;
    _analysis = NativeLevelAnalysis();
    _sampleBoundary = null;
    _lastSequence = -1;
    _emit(const AudioEvent.state(CaptureState.requesting));
    try {
      // SessionController can restart immediately while the old microphone closes.
      await _stopping;
      for (final previous in _pendingReleases.toList()) {
        await _release(previous);
      }
      if (!_current(ticket)) return;
      final allowed = await (_permission ??= AudioRecorder()).hasPermission();
      if (!_current(ticket)) return;
      if (!allowed) {
        await _end(CaptureState.error, 'permission_denied');
        return;
      }
      final settings = await _channel.invokeMapMethod<String, Object?>(
        'start',
        {'session': ticket, 'noiseReductionEnabled': noiseReductionEnabled},
      );
      if (!_current(ticket)) {
        await _release(ticket);
        return;
      }
      if (settings == null)
        throw const FormatException('Missing audio settings');
      _emit(AudioEvent.settings(settings));
      _running = true;
      _emit(const AudioEvent.state(CaptureState.running));
      if (!noiseReductionEnabled)
        _analysis.invalidate('noise_reduction_unavailable');
      _emit(AudioEvent.analysis(_analysis.snapshot));
      _missingTicks = 0;
      _watchdog = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!_current(ticket)) return;
        _missingTicks++;
        if (_missingTicks == 3) {
          _analysis.invalidate('input_gap');
          _emit(AudioEvent.analysis(_analysis.snapshot));
        }
        if (_missingTicks >= 15) {
          unawaited(_end(CaptureState.error, 'frame_timeout'));
        }
      });
    } on PlatformException catch (error) {
      if (_current(ticket)) await _end(CaptureState.error, error.code);
    } on MissingPluginException {
      if (_current(ticket)) await _end(CaptureState.error, 'unsupported');
    } catch (_) {
      if (_current(ticket)) await _end(CaptureState.error, 'processing_error');
    }
  }

  Future<void> _onNativeEvent(MethodCall call) async {
    final args = call.arguments;
    if (_disposed || args is! Map || args['session'] != _session) return;
    if (call.method == 'state') {
      final state = args['state'];
      if (state == 'idle' || state == 'error') {
        await _end(
          state == 'idle' ? CaptureState.idle : CaptureState.error,
          args['reason'] is String ? args['reason'] as String : 'input_ended',
        );
      }
      return;
    }
    if (call.method != 'frames' || !_running) return;
    try {
      final frames = args['frames'];
      if (frames is! List || frames.length > 100) {
        throw const FormatException('Invalid audio batch');
      }
      final level = args['level'];
      if (level != null) {
        if (level is! Map) throw const FormatException('Invalid level');
        final rms = level['rms'], peak = level['peak'];
        final dbfs = level['dbfs'], normalized = level['normalized'];
        final count = level['sampleCount'];
        if (rms is! num ||
            !rms.isFinite ||
            rms < 0 ||
            peak is! num ||
            !peak.isFinite ||
            peak < 0 ||
            (dbfs != null && (dbfs is! num || !dbfs.isFinite)) ||
            normalized is! num ||
            !normalized.isFinite ||
            normalized < 0 ||
            normalized > 1 ||
            count is! int ||
            count <= 0) {
          throw const FormatException('Invalid level values');
        }
        _emit(
          AudioEvent.level(
            rms: rms.toDouble(),
            peak: peak.toDouble(),
            dbfs: (dbfs as num?)?.toDouble(),
            normalized: normalized.toDouble(),
            sampleCount: count,
          ),
        );
      }
      if (level == null && frames.isEmpty) return;
      if (!_noiseReduction) {
        _missingTicks = 0;
        return;
      }
      var accepted = false;
      for (final raw in frames) {
        if (raw is! Map) throw const FormatException('Invalid analysis frame');
        final frame = Map<String, Object?>.from(raw);
        final seq = frame['seq'];
        _analysis.add(
          frame,
          collect:
              _sampleBoundary != null && seq is int && seq > _sampleBoundary!,
        );
        if (seq is int && seq > _lastSequence) {
          _lastSequence = seq;
          accepted = true;
        }
      }
      if (accepted) {
        _missingTicks = 0;
        _emit(AudioEvent.analysis(_analysis.snapshot));
      }
    } catch (_) {
      await _end(CaptureState.error, 'invalid_samples');
    }
  }

  @override
  Future<void> sampleEnvironment() async {
    final ticket = _session;
    if (ticket == null || !_running || !_noiseReduction) {
      throw StateError('Capture is not ready');
    }
    final request = ++_sampleRequest;
    _sampleBoundary = null;
    _analysis.sample();
    _emit(AudioEvent.analysis(_analysis.snapshot));
    try {
      final boundary = await _channel.invokeMethod<int>('sampleBoundary', {
        'session': ticket,
      });
      if (!_current(ticket) || request != _sampleRequest) return;
      if (boundary == null || boundary < -1)
        throw const FormatException('Invalid sample boundary');
      _sampleBoundary = boundary;
    } catch (_) {
      if (_current(ticket) && request == _sampleRequest) {
        _analysis.cancel();
        rethrow;
      }
    }
  }

  @override
  Future<void> cancelEnvironment() async {
    ++_sampleRequest;
    _sampleBoundary = null;
    _analysis.cancel();
    if (_running) _emit(AudioEvent.analysis(_analysis.snapshot));
  }

  Future<void> _release(int ticket) async {
    _pendingReleases.add(ticket);
    try {
      await _channel.invokeMethod<void>('stop', {'session': ticket});
    } on MissingPluginException {
      // No native capture exists on an unsupported platform.
    }
    _pendingReleases.remove(ticket);
  }

  Future<void> _end(CaptureState state, String? reason) {
    final ticket = _session;
    _session = null;
    _running = false;
    ++_sampleRequest;
    _sampleBoundary = null;
    _watchdog?.cancel();
    _watchdog = null;
    _emit(AudioEvent.state(state, reason: reason));
    if (ticket != null) {
      _stopping = _stopping.then((_) => _release(ticket)).catchError((
        Object _,
      ) {
        if (_session == null) {
          _emit(
            const AudioEvent.state(
              CaptureState.error,
              reason: 'processing_error',
            ),
          );
        }
      });
    }
    return _stopping;
  }

  @override
  Future<void> stop() => _end(CaptureState.idle, null);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The permission dialog itself makes the app inactive, so wait for background.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_end(CaptureState.idle, 'app_backgrounded'));
    }
  }

  @override
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    try {
      await stop();
    } finally {
      _channel.setMethodCallHandler(null);
      await _permission?.dispose();
      await _events.close();
    }
  }
}
