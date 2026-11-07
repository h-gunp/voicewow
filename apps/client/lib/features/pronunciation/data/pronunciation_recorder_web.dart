import 'dart:js_interop';

import 'pronunciation_recorder_contract.dart';

PronunciationRecorder createPronunciationRecorder() =>
    WebPronunciationRecorder();

class WebPronunciationRecorder implements PronunciationRecorder {
  _PronunciationSession? _session;
  bool _disposed = false;
  int _generation = 0;

  _PronunciationSession get _bridge {
    if (_disposed) throw StateError('발음 녹음기가 종료됐다.');
    return _session ??=
        _pronunciation?.createSession() ??
        (throw StateError('발음 분석 모듈을 불러오지 못했다. 새로고침해야 한다.'));
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error) {
      final message = error.toString();
      throw StateError(
        RegExp(r'[가-힣]').hasMatch(message)
            ? message
            : '발음 분석을 실행하지 못했다. 마이크 권한과 연결을 확인해야 한다.',
      );
    }
  }

  @override
  Future<void> prepare({void Function(String)? onProgress}) => _run(() async {
    final ticket = ++_generation;
    await _bridge
        .prepare(
          ((JSString message) {
            if (!_disposed && ticket == _generation)
              onProgress?.call(message.toDart);
          }).toJS,
        )
        .toDart;
  });

  @override
  Future<void> start({
    required void Function() onLimit,
    required void Function(String) onError,
  }) => _run(() async {
    final ticket = ++_generation;
    await _bridge
        .start(
          (() {
            if (!_disposed && ticket == _generation) onLimit();
          }).toJS,
          ((JSString message) {
            if (!_disposed && ticket == _generation) onError(message.toDart);
          }).toJS,
        )
        .toDart;
  });

  @override
  Future<List<String>> finish() => _run(() async {
    final result = await _bridge.finish().toDart;
    return result.toDart.map((phone) => phone.toDart).toList(growable: false);
  });

  @override
  Future<void> play() => _run(() async {
    await _bridge.play().toDart;
  });

  @override
  Future<void> cancel() => _run(() async {
    ++_generation;
    await _session?.cancel().toDart;
  });

  @override
  Future<void> dispose() => _run(() async {
    _disposed = true;
    ++_generation;
    final session = _session;
    _session = null;
    await session?.dispose().toDart;
  });
}

@JS('voiceMatePronunciation')
external _PronunciationBridge? get _pronunciation;

extension type _PronunciationBridge._(JSObject _) implements JSObject {
  external _PronunciationSession createSession();
}

extension type _PronunciationSession._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> prepare(JSFunction progress);
  external JSPromise<JSAny?> start(JSFunction onLimit, JSFunction onError);
  external JSPromise<JSArray<JSString>> finish();
  external JSPromise<JSAny?> play();
  external JSPromise<JSAny?> cancel();
  external JSPromise<JSAny?> dispose();
}
