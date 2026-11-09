import 'pronunciation_recorder_contract.dart';

PronunciationRecorder createPronunciationRecorder() => _UnavailableRecorder();

class _UnavailableRecorder implements PronunciationRecorder {
  Never _unavailable() => throw StateError('이 기기에서는 발음 녹음을 사용할 수 없다.');
  @override
  Future<void> prepare({void Function(String)? onProgress}) async =>
      _unavailable();
  @override
  Future<void> start({
    required void Function() onLimit,
    required void Function(String) onError,
    void Function(String)? onVoiceActivity,
  }) async => _unavailable();
  @override
  Future<List<String>> finish() async => _unavailable();
  @override
  Future<void> play() async => _unavailable();
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {}
}
