import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../audio/wav.dart';
import '../../../shared/native_tts_coordinator.dart';

/// A local device/permission failure, rather than a judgement of speaking skill.
class DeviceAudioException implements Exception {
  const DeviceAudioException(this.message);
  final String message;
  @override
  String toString() => message;
}

class GeneratedGuide {
  const GeneratedGuide({required this.path, required this.bytes});
  final String path;
  final Uint8List bytes;
  String get source => '기기의 한국어 읽기 예시';
}

class RecordedAudio {
  const RecordedAudio({
    required this.samples,
    required this.sampleRate,
    required this.path,
    required this.bytes,
  });
  final List<double> samples;
  final int sampleRate;
  final String path;
  final Uint8List bytes;
}

/// Android's TTS plugin encodes booleans as strings ("0" / "1"). A voice
/// requiring a download is also unsuitable even when it does not use a network
/// for each synthesis request.
bool isInstalledOfflineKoreanVoice(Map<dynamic, dynamic> voice) {
  final locale = '${voice['locale'] ?? ''}'.replaceAll('_', '-').toLowerCase();
  final flag = '${voice['network_required'] ?? ''}'.toLowerCase();
  final features = '${voice['features'] ?? ''}';
  return (locale == 'ko' || locale.startsWith('ko-')) &&
      (flag == '0' || flag == 'false') &&
      !features.contains('notInstalled');
}

/// PCM16 little-endian chunks may end halfway through a sample. Keep that byte
/// for the next chunk instead of dropping it or shifting every later sample.
class Pcm16StreamDecoder {
  int? _lowByte;

  List<double> add(Uint8List bytes) {
    final samples = <double>[];
    var index = 0;
    if (_lowByte != null && bytes.isNotEmpty) {
      samples.add(_signed(_lowByte! | (bytes[0] << 8)) / 32768.0);
      _lowByte = null;
      index = 1;
    }
    for (; index + 1 < bytes.length; index += 2) {
      samples.add(_signed(bytes[index] | (bytes[index + 1] << 8)) / 32768.0);
    }
    if (index < bytes.length) _lowByte = bytes[index];
    return samples;
  }

  void reset() => _lowByte = null;
  static int _signed(int value) => value >= 0x8000 ? value - 0x10000 : value;
}

/// Native Android recording, offline Korean TTS and local WAV playback.
///
/// Plugin objects are lazy: constructing this service never requests a
/// permission, opens the microphone or downloads/sends a script. Recordings and
/// synthesized examples live in one app-temporary directory, removed on dispose.
class DeviceAudioService {
  static const int recordingSampleRate = 16000;
  static const int maxRecordingSeconds = 20;
  static const int _maxSamples = recordingSampleRate * maxRecordingSeconds;

  AudioRecorder? _recorder;
  FlutterTts? _tts;
  NativeTtsLease? _guideLease;
  AudioPlayer? _player;
  Future<Directory>? _directory;
  final StreamController<String> _errors = StreamController<String>.broadcast();
  final Pcm16StreamDecoder _decoder = Pcm16StreamDecoder();
  StreamSubscription<Uint8List>? _stream;
  Timer? _recordLimit;
  final List<double> _samples = <double>[];
  Future<RecordedAudio>? _stopFuture;
  Future<void>? _cancelFuture;
  Completer<void>? _guideCancelled;
  bool _disposed = false,
      _starting = false,
      _recording = false,
      _guideBusy = false;
  int _recordGeneration = 0,
      _guideGeneration = 0,
      _playGeneration = 0,
      _fileNumber = 0;
  Object? _recordError;

  bool get isRecording => _recording;
  bool get isGenerating => _guideBusy;
  Stream<String> get errors => _errors.stream;

  void _checkOpen() {
    if (_disposed) {
      throw const DeviceAudioException('음성 기능이 종료됐어요. 화면을 다시 열어 주세요.');
    }
  }

  Future<Directory> _temporaryDirectory() {
    return _directory ??= () async {
      final root = await getTemporaryDirectory();
      return Directory(
        '${root.path}/voicemate_${DateTime.now().microsecondsSinceEpoch}',
      ).create(recursive: true);
    }();
  }

  /// Copy a bundled/demo WAV into this service's temporary scope for playback.
  Future<String> storeAudio(
    Uint8List bytes, {
    String name = 'audio.wav',
  }) async {
    _checkOpen();
    if (bytes.isEmpty) throw const DeviceAudioException('재생할 음성 파일이 비어 있어요.');
    final stem = name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final path = await _newPath(stem.isEmpty ? 'audio' : stem);
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  Future<String> _newPath(String kind) async {
    final directory = await _temporaryDirectory();
    return '${directory.path}/${kind}_${++_fileNumber}.wav';
  }

  Future<GeneratedGuide> generateGuide(String text) async {
    _checkOpen();
    final sentence = text.trim();
    if (sentence.isEmpty || sentence.runes.length > 100) {
      throw const DeviceAudioException('가이드는 1~100자의 짧은 문장으로 만들어 주세요.');
    }
    if (_recording || _starting || _guideBusy || _cancelFuture != null) {
      throw const DeviceAudioException('진행 중인 녹음이나 가이드를 마친 뒤 다시 시도해 주세요.');
    }
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw const DeviceAudioException(
        '기기 가이드 생성은 현재 안드로이드에서 지원해요. 준비된 예시로 연습할 수 있어요.',
      );
    }
    final ticket = ++_guideGeneration;
    _guideBusy = true;
    final cancelled = Completer<void>();
    final synthesisFailed = Completer<void>();
    _guideCancelled = cancelled;
    String? path;
    NativeTtsLease? lease;
    void checkGeneration() {
      if (_disposed || ticket != _guideGeneration) {
        throw const DeviceAudioException('가이드 만들기를 취소했어요.');
      }
    }

    try {
      await stopPlayback();
      checkGeneration();
      lease = await NativeTtsCoordinator.shared.acquire(
        NativeTtsKind.synthesis,
        cancelled: cancelled.future,
      );
      checkGeneration();
      if (lease == null) {
        throw const DeviceAudioException('음성 엔진을 사용할 수 없어요. 잠시 후 다시 시도해 주세요.');
      }
      _guideLease = lease;
      final tts = _tts = FlutterTts();
      NativeTtsCoordinator.shared.installHandler(lease, (call) async {
        if (call.method == 'synth.onError' &&
            lease?.issued == true &&
            !synthesisFailed.isCompleted) {
          // Android leaves synthesizeToFile pending after this error callback.
          synthesisFailed.complete();
        }
        return tts.platformCallHandler(call);
      });
      final installed = await tts.isLanguageInstalled('ko-KR');
      checkGeneration();
      if (installed != true && installed != 1) {
        throw const DeviceAudioException(
          '기기에 한국어 읽기 음성이 설치되지 않았어요. 안드로이드의 음성 출력 설정에서 한국어 음성을 설치하거나 준비된 예시를 사용해 주세요.',
        );
      }
      final rawVoices = await tts.getVoices;
      checkGeneration();
      final voices = rawVoices is List
          ? rawVoices
                .whereType<Map>()
                .where(isInstalledOfflineKoreanVoice)
                .toList()
          : <Map>[];
      if (voices.isEmpty) {
        throw const DeviceAudioException(
          '설치된 오프라인 한국어 음성을 찾지 못했어요. 한국어 음성 데이터를 설치하거나 준비된 예시를 사용해 주세요.',
        );
      }
      voices.sort((a, b) {
        int quality(dynamic value) {
          const labels = [
            'unknown',
            'very low',
            'low',
            'normal',
            'high',
            'very high',
          ];
          return int.tryParse('$value') ?? labels.indexOf('$value');
        }

        final aq = quality(a['quality']);
        final bq = quality(b['quality']);
        return bq.compareTo(aq);
      });
      final voice = voices.first;
      final languageSet = await tts.setLanguage('ko-KR');
      checkGeneration();
      final voiceSet = await tts.setVoice({
        'name': '${voice['name']}',
        'locale': '${voice['locale']}',
      });
      checkGeneration();
      if ((languageSet != 1 && languageSet != true) ||
          (voiceSet != 1 && voiceSet != true)) {
        throw const DeviceAudioException(
          '오프라인 한국어 음성을 선택하지 못했어요. 준비된 예시를 사용해 주세요.',
        );
      }
      await tts.setSpeechRate(0.45);
      checkGeneration();
      await tts.setPitch(1.0);
      checkGeneration();
      await tts.awaitSynthCompletion(true);
      checkGeneration();
      path = await _newPath('guide');
      checkGeneration();
      lease.issued = true;
      final completed = tts.synthesizeToFile(sentence, path, true).then((
        dynamic result,
      ) {
        if (result != 1 && result != true) {
          throw const DeviceAudioException(
            '기기에서 가이드 음성을 만들지 못했어요. 다시 시도해 주세요.',
          );
        }
      });
      await Future.any<void>([
        completed,
        synthesisFailed.future.then(
          (_) => throw const DeviceAudioException(
            '기기에서 가이드 음성을 만들지 못했어요. 다시 시도해 주세요.',
          ),
        ),
        cancelled.future.then(
          (_) => throw const DeviceAudioException('가이드 만들기를 취소했어요.'),
        ),
      ]).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw const DeviceAudioException(
            '가이드 준비 시간이 오래 걸려 중지했어요. 문장을 줄여 다시 시도해 주세요.',
          );
        },
      );
      if (_disposed || ticket != _guideGeneration) {
        throw const DeviceAudioException('가이드 만들기를 취소했어요.');
      }
      final bytes = await File(path).readAsBytes();
      if (bytes.length < 44 ||
          String.fromCharCodes(bytes.take(4)) != 'RIFF' ||
          String.fromCharCodes(bytes.skip(8).take(4)) != 'WAVE') {
        throw const DeviceAudioException(
          '이 기기의 가이드 음성을 분석할 수 없어요. 준비된 예시로 연습해 주세요.',
        );
      }
      return GeneratedGuide(path: path, bytes: bytes);
    } on DeviceAudioException {
      if (ticket == _guideGeneration) await _stopTts(lease);
      if (path != null) await _deleteFile(path);
      rethrow;
    } catch (_) {
      if (ticket == _guideGeneration) await _stopTts(lease);
      if (path != null) await _deleteFile(path);
      throw const DeviceAudioException(
        '한국어 가이드 생성에 문제가 생겼어요. 음성 출력 설정을 확인하거나 준비된 예시를 사용해 주세요.',
      );
    } finally {
      lease?.releaseUnissued();
      if (identical(_guideLease, lease)) _guideLease = null;
      if (ticket == _guideGeneration) {
        _guideBusy = false;
        _guideCancelled = null;
      }
    }
  }

  Future<void> cancelGuide() async {
    _guideGeneration++;
    _guideBusy = false;
    final cancellation = _guideCancelled;
    _guideCancelled = null;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    await _stopTts(_guideLease);
  }

  Future<void> _stopTts(NativeTtsLease? lease) async {
    try {
      final tts = _tts;
      if (lease != null && lease.isCurrent && lease.issued && tts != null) {
        await tts.stop();
      }
    } catch (_) {
      /* already stopped by the engine */
    }
  }

  Future<void> start({
    required void Function(List<double> samples) onSamples,
    void Function()? onLimitReached,
    void Function(String message)? onError,
  }) async {
    _checkOpen();
    if (_recording || _starting || _guideBusy || _cancelFuture != null) {
      throw const DeviceAudioException('진행 중인 녹음이나 가이드를 먼저 마쳐 주세요.');
    }
    final ticket = ++_recordGeneration;
    _starting = true;
    try {
      await stopPlayback();
      if (_disposed || ticket != _recordGeneration) return;
      final recorder = _recorder ??= AudioRecorder();
      if (!await recorder.hasPermission()) {
        throw const DeviceAudioException(
          '마이크 권한이 필요해요. 앱 권한 설정에서 마이크를 허용해 주세요.',
        );
      }
      if (_disposed || ticket != _recordGeneration) return;
      if (!await recorder.isEncoderSupported(AudioEncoder.pcm16bits)) {
        throw const DeviceAudioException(
          '이 기기에서 실시간 녹음을 지원하지 않아요. 다른 기기에서 확인해 주세요.',
        );
      }
      if (_disposed || ticket != _recordGeneration) return;
      _samples.clear();
      _decoder.reset();
      _recordError = null;
      _stopFuture = null;
      bool formatRejected = false;
      await recorder.setOnConfigChanged((config) {
        if (config.sampleRate == recordingSampleRate &&
            config.numChannels == 1 &&
            config.encoder == AudioEncoder.pcm16bits) {
          return;
        }
        formatRejected = true;
        if (_recording && ticket == _recordGeneration) {
          onError?.call('기기에서 녹음 형식을 바꿔 분석을 중지했어요. 다른 기기에서 확인해 주세요.');
          unawaited(cancel());
        }
      });
      if (_disposed || ticket != _recordGeneration) return;
      final source = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: recordingSampleRate,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
          streamBufferSize: 1280,
        ),
      );
      if (_disposed || ticket != _recordGeneration) {
        await recorder.cancel();
        return;
      }
      if (formatRejected) {
        await recorder.cancel();
        throw const DeviceAudioException(
          '이 기기의 녹음 형식을 분석할 수 없어요. 다른 기기에서 확인해 주세요.',
        );
      }
      _recording = true;
      bool limitNotified = false;
      Future<void> endAtLimit() async {
        if (limitNotified || ticket != _recordGeneration || !_recording) return;
        limitNotified = true;
        try {
          await stop();
          if (!_disposed && ticket == _recordGeneration) onLimitReached?.call();
        } catch (_) {
          if (!_disposed && ticket == _recordGeneration) {
            onError?.call('녹음된 소리를 읽지 못했어요. 다시 시도해 주세요.');
          }
        }
      }

      _stream = source.listen(
        (bytes) {
          if (!_recording || _disposed || ticket != _recordGeneration) return;
          final decoded = _decoder.add(bytes);
          final remaining = _maxSamples - _samples.length;
          if (remaining <= 0) {
            unawaited(endAtLimit());
            return;
          }
          final accepted = decoded.length <= remaining
              ? decoded
              : decoded.sublist(0, remaining);
          _samples.addAll(accepted);
          if (accepted.isNotEmpty) {
            onSamples(List<double>.unmodifiable(accepted));
          }
          if (_samples.length >= _maxSamples) unawaited(endAtLimit());
        },
        onError: (Object error) {
          if (_disposed || ticket != _recordGeneration || !_recording) return;
          _recordError = error;
          onError?.call('마이크 연결이 끊겼어요. 다시 녹음해 주세요.');
          unawaited(cancel());
        },
        onDone: () {
          if (_recording &&
              _stopFuture == null &&
              ticket == _recordGeneration) {
            unawaited(endAtLimit());
          }
        },
      );
      _recordLimit = Timer(
        const Duration(seconds: maxRecordingSeconds),
        () => unawaited(endAtLimit()),
      );
    } on DeviceAudioException {
      rethrow;
    } catch (_) {
      if (ticket == _recordGeneration) {
        try {
          await _recorder?.cancel();
        } catch (_) {
          /* release best effort */
        }
      }
      throw const DeviceAudioException('마이크를 시작하지 못했어요. 연결과 앱 권한을 확인해 주세요.');
    } finally {
      if (ticket == _recordGeneration) _starting = false;
    }
  }

  Future<RecordedAudio> stop() {
    _checkOpen();
    return _stopFuture ??= _finishStop();
  }

  Future<RecordedAudio> _finishStop() async {
    if (!_recording) {
      throw const DeviceAudioException('녹음된 소리가 없어요. 녹음을 먼저 시작해 주세요.');
    }
    final ticket = _recordGeneration;
    final stream = _stream;
    _recordLimit?.cancel();
    _recordLimit = null;
    try {
      await _recorder?.stop();
    } finally {
      if (ticket == _recordGeneration) {
        _recording = false;
        _stream = null;
      }
      await stream?.cancel();
    }
    if (_disposed || ticket != _recordGeneration) {
      throw const DeviceAudioException('녹음을 취소했어요.');
    }
    if (_recordError != null || _samples.isEmpty) {
      throw const DeviceAudioException('녹음된 소리를 읽지 못했어요. 다시 녹음해 주세요.');
    }
    final samples = List<double>.unmodifiable(_samples);
    final bytes = encodeWav(samples, recordingSampleRate);
    final path = await _newPath('recording');
    await File(path).writeAsBytes(bytes, flush: true);
    return RecordedAudio(
      samples: samples,
      sampleRate: recordingSampleRate,
      path: path,
      bytes: bytes,
    );
  }

  Future<void> cancel() {
    return _cancelFuture ??= _finishCancel().whenComplete(() {
      _cancelFuture = null;
    });
  }

  Future<void> _finishCancel() async {
    _recordGeneration++;
    _recordLimit?.cancel();
    _recordLimit = null;
    _recording = false;
    _starting = false;
    final stream = _stream;
    _stream = null;
    await stream?.cancel();
    try {
      await _recorder?.cancel();
    } catch (_) {
      /* may already be stopped */
    }
    _samples.clear();
    _decoder.reset();
    _stopFuture = null;
  }

  /// By default returns after starting playback; later failures are in [errors].
  /// [waitForCompletion] keeps an exclusive practice flow busy until playback ends.
  /// [start]/[end] refer to the original WAV, including its leading silence.
  Future<void> play(
    String path, {
    Duration? start,
    Duration? end,
    bool waitForCompletion = false,
  }) async {
    _checkOpen();
    if (_recording || _starting) {
      throw const DeviceAudioException('녹음을 마친 뒤 소리를 재생해 주세요.');
    }
    if ((start?.isNegative ?? false) ||
        (end != null && end <= (start ?? Duration.zero))) {
      throw const DeviceAudioException('재생할 구간을 다시 선택해 주세요.');
    }
    final ticket = ++_playGeneration;
    final player = _player ??= AudioPlayer();
    try {
      await player.stop();
      if (_disposed || ticket != _playGeneration) return;
      final duration = await player.setFilePath(path);
      if (_disposed || ticket != _playGeneration) return;
      if (duration != null && start != null && start >= duration) {
        throw const DeviceAudioException('재생할 소리 구간이 없어요. 다른 구간을 선택해 주세요.');
      }
      final boundedEnd = duration != null && end != null && end > duration
          ? duration
          : end;
      await player.setClip(start: start, end: boundedEnd);
      if (_disposed || ticket != _playGeneration) return;
      await player.seek(Duration.zero);
      if (_disposed || ticket != _playGeneration) return;
      final playback = player.play();
      if (waitForCompletion) {
        await playback;
      } else {
        unawaited(
          playback.catchError((Object error, StackTrace stack) {
            if (!_disposed && ticket == _playGeneration) {
              _errors.add('소리를 재생하지 못했어요. 다시 시도해 주세요.');
            }
          }),
        );
      }
    } on DeviceAudioException {
      rethrow;
    } catch (_) {
      if (!_disposed && ticket == _playGeneration) {
        throw const DeviceAudioException('소리를 재생하지 못했어요. 다시 시도해 주세요.');
      }
    }
  }

  Future<void> stopPlayback() async {
    _playGeneration++;
    try {
      await _player?.stop();
    } catch (_) {
      /* interrupted or already stopped */
    }
  }

  Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      /* temporary cleanup */
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await cancelGuide();
    await cancel();
    await stopPlayback();
    try {
      await _recorder?.dispose();
    } catch (_) {
      /* continue cleanup */
    }
    try {
      await _player?.dispose();
    } catch (_) {
      /* continue cleanup */
    }
    final directory = _directory;
    if (directory != null) {
      try {
        final value = await directory;
        if (await value.exists()) await value.delete(recursive: true);
      } catch (_) {
        /* OS may reclaim app cache later */
      }
    }
    await _errors.close();
  }
}
