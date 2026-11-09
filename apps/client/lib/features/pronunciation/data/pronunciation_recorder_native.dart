import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../../prosody/services/device_audio.dart';
import 'pronunciation_recorder_contract.dart';
import '../domain/ipa_phones.dart';
import 'pronunciation_recorder_stub.dart' as unsupported;

PronunciationRecorder createPronunciationRecorder() => Platform.isAndroid
    ? NativePronunciationRecorder()
    : unsupported.createPronunciationRecorder();

class NativePronunciationRecorder implements PronunciationRecorder {
  NativePronunciationRecorder({DeviceAudioService? audio})
    : _audio =
          audio ??
          DeviceAudioService(
            noiseReductionEnabled: false,
            voiceActivityEnabled: false,
          ) {
    if (!_handlerInstalled) {
      _handlerInstalled = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'progress' || call.arguments is! Map) return;
        final args = call.arguments as Map;
        final recorder = _progressOwners[args['session']];
        if (recorder != null &&
            recorder._generation == args['request'] &&
            !recorder._disposed &&
            args['message'] is String) {
          recorder._onProgress?.call(args['message'] as String);
        }
      });
    }
  }

  static const _channel = MethodChannel('voicemate/pronunciation');
  static final _progressOwners = <int, NativePronunciationRecorder>{};
  static bool _handlerInstalled = false;
  static int _nextSession = 0;
  final int _session = ++_nextSession;
  final DeviceAudioService _audio;
  int _generation = 0;
  bool _disposed = false, _prepared = false, _recording = false, _busy = false;
  String? _path;
  void Function(String)? _onProgress;
  Future<void>? _cancelling;
  Future<void>? _pendingStart;

  Map<String, Object> _arguments(int ticket) => {
    'session': _session,
    'request': ticket,
  };

  void _check(int ticket) {
    if (_disposed || ticket != _generation) {
      throw const DeviceAudioException('음성 분석을 취소했다.');
    }
  }

  @override
  Future<void> prepare({void Function(String)? onProgress}) async {
    if (_disposed || _busy || _recording) {
      throw const DeviceAudioException('진행 중인 음성 작업을 먼저 마쳐야 한다.');
    }
    final ticket = ++_generation;
    _busy = true;
    _prepared = false;
    _onProgress = onProgress;
    _progressOwners[_session] = this;
    try {
      await _cancelling;
      _check(ticket);
      await _channel.invokeMethod<void>('prepare', _arguments(ticket));
      _check(ticket);
      _prepared = true;
    } on MissingPluginException {
      throw const DeviceAudioException(
        '이 기기에서는 발음 분석을 지원하지 않는다. 안드로이드나 웹에서 사용할 수 있다.',
      );
    } on PlatformException catch (error) {
      throw DeviceAudioException(
        error.message ?? '분석 모델을 준비하지 못했다. 다시 시도해야 한다.',
      );
    } finally {
      if (ticket == _generation) {
        _busy = false;
        _onProgress = null;
        _progressOwners.remove(_session);
      }
    }
  }

  @override
  Future<void> start({
    required void Function() onLimit,
    required void Function(String) onError,
    void Function(String)? onVoiceActivity,
  }) async {
    if (!_prepared || _busy || _recording || _disposed) {
      throw const DeviceAudioException('분석 준비를 마친 뒤 녹음해야 한다.');
    }
    final ticket = ++_generation;
    _busy = true;
    _path = null;
    try {
      await _cancelling;
      _check(ticket);
      // A late native start can cancel its recorder; drain it before reusing that recorder.
      await _pendingStart?.catchError((Object _) {});
      _check(ticket);
      String? previousActivity;
      final starting = _audio.start(
        onSamples: (_) {
          if (_disposed || ticket != _generation || !_recording) return;
          final activity = _audio.recentVoiceActivity;
          if (activity != previousActivity &&
              const {'speech', 'nonSpeech', 'uncertain'}.contains(activity)) {
            previousActivity = activity;
            onVoiceActivity?.call(activity!);
          }
        },
        onLimitReached: () {
          if (!_disposed && ticket == _generation) onLimit();
        },
        onError: (message) {
          if (!_disposed && ticket == _generation) onError(message);
        },
      );
      _pendingStart = starting;
      try {
        await starting;
      } finally {
        if (identical(_pendingStart, starting)) _pendingStart = null;
      }
      _check(ticket);
      _recording = true;
    } finally {
      if (ticket == _generation) _busy = false;
    }
  }

  @override
  Future<List<String>> finish() async {
    if (!_recording || _busy || _disposed) {
      throw const DeviceAudioException('녹음을 먼저 시작해야 한다.');
    }
    final ticket = _generation;
    _busy = true;
    _recording = false;
    try {
      final recording = await _audio.stop();
      _check(ticket);
      _path = recording.path;
      final phones = await _channel.invokeListMethod<String>('recognize', {
        ..._arguments(ticket),
        'samples': Float32List.fromList(recording.samples),
        'sampleRate': recording.sampleRate,
        if (localAudioDiagnosticsEnabled &&
            recording.diagnosticsPcm48 != null) ...{
          'diagnosticRawPcm48': recording.diagnosticsPcm48,
          if (recording.speechFrames != null)
            'diagnosticSpeech': Int32List.fromList(recording.speechFrames!),
        },
      });
      _check(ticket);
      if (phones == null) throw const DeviceAudioException('분석 결과를 읽지 못했다.');
      return ipaToPhones(phones);
    } on PlatformException catch (error) {
      throw DeviceAudioException(error.message ?? '음성을 분석하지 못했다. 다시 녹음해야 한다.');
    } finally {
      if (ticket == _generation) _busy = false;
    }
  }

  @override
  Future<void> play() async {
    if (_disposed || _busy || _recording || _path == null) {
      throw const DeviceAudioException('재생할 녹음이 없다.');
    }
    final ticket = _generation;
    _busy = true;
    try {
      await _audio.play(_path!, waitForCompletion: true);
      _check(ticket);
    } finally {
      if (ticket == _generation) _busy = false;
    }
  }

  @override
  Future<void> cancel() {
    return _cancelling ??= _cancel().whenComplete(() => _cancelling = null);
  }

  Future<void> _cancel() async {
    _generation++;
    _busy = false;
    _recording = false;
    _prepared = false;
    _path = null;
    _onProgress = null;
    _progressOwners.remove(_session);
    await Future.wait<void>([
      _audio.cancel(),
      _audio.stopPlayback(),
      _channel
          .invokeMethod<void>('cancel', {'session': _session})
          .catchError((Object _) {}),
    ]);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await cancel();
    try {
      await _channel.invokeMethod<void>('dispose', {'session': _session});
    } on MissingPluginException {
      // No native engine was created on unsupported platforms.
    } on PlatformException {
      // Local recorder cleanup must finish even after channel teardown.
    } finally {
      await _audio.dispose();
    }
  }
}
