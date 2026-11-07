abstract interface class PronunciationRecorder {
  Future<void> prepare({void Function(String)? onProgress});
  Future<void> start({
    required void Function() onLimit,
    required void Function(String) onError,
  });
  Future<List<String>> finish();
  Future<void> play();
  Future<void> cancel();
  Future<void> dispose();
}
