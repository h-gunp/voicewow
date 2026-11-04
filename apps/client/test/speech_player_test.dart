import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:voicemate/features/pronunciation/data/speech_player.dart';
import 'package:voicemate/features/pronunciation/data/speech_transport.dart';
import 'package:voicemate/features/pronunciation/data/speech_transport_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late DeviceSpeechPlayer player;
  late List<MethodCall> calls;
  late List<_CallWaiter> waiters;
  late Future<Object?> Function(MethodCall) platform;

  Future<void> event(String method, [Object? arguments]) async {
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall(method, arguments)),
      null,
    );
  }

  int count(String method) =>
      calls.where((call) => call.method == method).length;

  Future<void> reached(String method, {int occurrence = 1}) {
    if (count(method) >= occurrence) return Future.value();
    final waiter = _CallWaiter(method, occurrence);
    waiters.add(waiter);
    return waiter.done.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => throw StateError(
        'Expected $method #$occurrence; received '
        '${calls.map((call) => call.method).join(', ')}',
      ),
    );
  }

  Future<Object?> normalPlatform(MethodCall call) async {
    if (call.method == 'isLanguageAvailable') return true;
    if (call.method == 'stop') {
      scheduleMicrotask(() => unawaited(event('speak.onCancel')));
    }
    return 1;
  }

  setUp(() {
    calls = [];
    waiters = [];
    platform = normalPlatform;
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      for (final waiter in waiters) {
        if (!waiter.done.isCompleted &&
            count(waiter.method) >= waiter.occurrence) {
          waiter.done.complete();
        }
      }
      return platform(call);
    });
    player = DeviceSpeechPlayer();
  });

  tearDown(() async {
    await player.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  for (final acknowledgement in <Object?>[1, null]) {
    test(
      'acknowledgement $acknowledgement stays preparing until actual start',
      () async {
        platform = (call) async => call.method == 'speak'
            ? acknowledgement
            : await normalPlatform(call);
        expect(player.playback.value.phase, SpeechPhase.ready);
        final outcome = player.speak('같이 가요');
        expect(player.playback.value.phase, SpeechPhase.preparing);
        var resolved = false;
        unawaited(outcome.then((_) => resolved = true));
        await reached('speak');
        await Future<void>.delayed(Duration.zero);
        expect(resolved, isFalse);
        expect(player.playback.value.phase, SpeechPhase.preparing);

        await event('speak.onStart');
        expect(await outcome, SpeechResult.started);
        expect(player.playback.value.phase, SpeechPhase.playing);
        final spoken = calls
            .singleWhere((call) => call.method == 'speak')
            .arguments;
        expect(spoken is Map ? spoken['text'] : spoken, '같이 가요');
        expect(
          calls.singleWhere((call) => call.method == 'setLanguage').arguments,
          'ko-KR',
        );

        await event('speak.onComplete');
        expect(player.playback.value.phase, SpeechPhase.ready);
        expect(player.playback.value.result, isNull);
      },
    );
  }

  test(
    'slow practice configures a lower rate and waits for its own callbacks',
    () async {
      final first = player.speak('국물');
      await reached('speak');
      await event('speak.onStart');
      expect(await first, SpeechResult.started);
      await event('speak.onComplete');
      final second = player.speak('국물', slow: true);
      await reached('speak', occurrence: 2);
      expect(player.playback.value.phase, SpeechPhase.preparing);
      await event('speak.onStart');
      expect(await second, SpeechResult.started);
      await event('speak.onComplete');
      final rates = calls
          .where((call) => call.method == 'setSpeechRate')
          .map((call) => call.arguments as double)
          .toList();
      expect(rates, hasLength(2));
      expect(rates.last, lessThan(rates.first));
      expect(rates.every((rate) => rate > 0), isTrue);
    },
  );

  test(
    'an error before start restores ready and reports unavailable',
    () async {
      final outcome = player.speak('같이 가요');
      await reached('speak');
      await event('speak.onError', 'language-unavailable');
      expect(await outcome, SpeechResult.unavailable);
      expect(player.playback.value.phase, SpeechPhase.ready);
      expect(player.playback.value.result, SpeechResult.unavailable);
    },
  );

  test('an error after start also resets the lifecycle to ready', () async {
    final outcome = player.speak('같이 가요');
    await reached('speak');
    await event('speak.onStart');
    expect(await outcome, SpeechResult.started);
    await event('speak.onError', 'engine-failed');
    expect(player.playback.value.phase, SpeechPhase.ready);
    expect(player.playback.value.result, SpeechResult.unavailable);
  });

  test('missing Korean voice never issues a speak command', () async {
    platform = (call) async => call.method == 'isLanguageAvailable'
        ? false
        : await normalPlatform(call);
    expect(await player.speak('같이 가요'), SpeechResult.unavailable);
    expect(count('speak'), 0);
    expect(player.playback.value.phase, SpeechPhase.ready);
  });

  test(
    'a rejected speak acknowledgement restores ready without a start event',
    () async {
      platform = (call) async =>
          call.method == 'speak' ? 0 : await normalPlatform(call);
      expect(await player.speak('같이 가요'), SpeechResult.unavailable);
      expect(count('speak'), 1);
      expect(player.playback.value.phase, SpeechPhase.ready);
      expect(player.playback.value.result, SpeechResult.unavailable);
    },
  );

  test(
    'a platform initialization exception is unavailable and does not escape',
    () async {
      platform = (call) async {
        if (call.method == 'isLanguageAvailable') {
          throw PlatformException(code: 'voice-initialization-failed');
        }
        return await normalPlatform(call);
      };
      expect(await player.speak('같이 가요'), SpeechResult.unavailable);
      expect(count('speak'), 0);
      expect(player.playback.value.phase, SpeechPhase.ready);
    },
  );

  test(
    'a speak exception restores ready and does not escape into the UI',
    () async {
      platform = (call) async {
        if (call.method == 'speak')
          throw PlatformException(code: 'voice-engine-failed');
        return await normalPlatform(call);
      };
      expect(await player.speak('같이 가요'), SpeechResult.unavailable);
      expect(player.playback.value.phase, SpeechPhase.ready);
    },
  );

  test(
    'stop during language lookup cancels before speech can be queued',
    () async {
      final available = Completer<bool>();
      platform = (call) async => call.method == 'isLanguageAvailable'
          ? await available.future
          : await normalPlatform(call);
      final outcome = player.speak('같이 가요');
      await reached('isLanguageAvailable');
      await player.stop();
      expect(await outcome, SpeechResult.cancelled);
      expect(player.playback.value.phase, SpeechPhase.ready);
      available.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(count('speak'), 0);
    },
  );

  test('dispose during language lookup cancels pending speech', () async {
    final available = Completer<bool>();
    platform = (call) async => call.method == 'isLanguageAvailable'
        ? await available.future
        : await normalPlatform(call);
    final outcome = player.speak('같이 가요');
    await reached('isLanguageAvailable');
    await player.dispose();
    expect(await outcome, SpeechResult.cancelled);
    available.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(count('speak'), 0);
  });

  test(
    'retired callbacks drain before a second utterance can be issued',
    () async {
      platform = (call) async =>
          call.method == 'stop' ? 1 : await normalPlatform(call);
      expect(await platform(const MethodCall('isLanguageAvailable')), isTrue);
      final first = player.speak('첫 문장');
      await reached('speak');
      final stopping = player.stop();
      await reached('stop');
      expect(await first, SpeechResult.cancelled);
      expect(player.playback.value.phase, SpeechPhase.ready);

      final second = player.speak('다음 문장');
      await Future<void>.delayed(Duration.zero);
      expect(count('speak'), 1);
      expect(player.playback.value.phase, SpeechPhase.preparing);
      // A queued old utterance starting after stop is cancelled, not attributed
      // to the new request waiting behind it.
      await event('speak.onStart');
      await reached('stop', occurrence: 2);
      expect(count('speak'), 1);
      expect(player.playback.value.phase, SpeechPhase.preparing);
      await event('speak.onCancel');
      await stopping;

      await reached('speak', occurrence: 2);
      expect(player.playback.value.phase, SpeechPhase.preparing);
      await event('speak.onStart');
      expect(await second, SpeechResult.started);
      expect(player.playback.value.phase, SpeechPhase.playing);
      await event('speak.onComplete');
      expect(player.playback.value.phase, SpeechPhase.ready);
    },
  );

  test(
    'reclaims callbacks after another FlutterTts client used the channel',
    () async {
      final first = player.speak('첫 문장');
      await reached('speak');
      await event('speak.onStart');
      expect(await first, SpeechResult.started);
      await event('speak.onComplete');
      FlutterTts(); // A file-synthesis feature installs its own global handler.

      final second = player.speak('다음 문장');
      await reached('speak', occurrence: 2);
      await event('speak.onStart');
      expect(await second, SpeechResult.started);
      expect(player.playback.value.phase, SpeechPhase.playing);
      await event('speak.onComplete');
      expect(player.playback.value.phase, SpeechPhase.ready);
    },
  );

  test(
    'file synthesis events cannot masquerade as playback lifecycle',
    () async {
      final outcome = player.speak('같이 가요');
      await reached('speak');
      await event('synth.onStart');
      await event('synth.onComplete');
      await event('synth.onError', 'old-synthesis-error');
      expect(player.playback.value.phase, SpeechPhase.preparing);
      await event('speak.onStart');
      expect(await outcome, SpeechResult.started);
      await event('synth.onComplete');
      expect(player.playback.value.phase, SpeechPhase.playing);
      await event('speak.onComplete');
      expect(player.playback.value.phase, SpeechPhase.ready);
    },
  );

  test(
    'preparation watchdog stops queued speech and ignores a late start',
    () async {
      await player.dispose();
      player = DeviceSpeechPlayer(
        preparationTimeout: const Duration(milliseconds: 100),
        transport: NativeSpeechTransport(
          cancellationTimeout: const Duration(milliseconds: 20),
        ),
      );
      platform = (call) async =>
          call.method == 'stop' ? 1 : await normalPlatform(call);
      expect(await platform(const MethodCall('isLanguageAvailable')), isTrue);
      final outcome = player.speak('같이 가요');
      await reached('speak');
      expect(await outcome, SpeechResult.unavailable);
      await reached('stop');
      expect(player.playback.value.phase, SpeechPhase.ready);
      expect(player.playback.value.result, SpeechResult.unavailable);
      await event('speak.onStart');
      await reached('stop', occurrence: 2);
      expect(player.playback.value.phase, SpeechPhase.ready);
      await event('speak.onCancel');
    },
  );

  test(
    'tagged callbacks from an old request cannot change a newer lifecycle',
    () async {
      await player.dispose();
      final transport = _TaggedTransport();
      player = DeviceSpeechPlayer(transport: transport);
      final first = player.speak('첫 문장');
      final firstId = transport.requests.single;
      await player.stop();
      expect(await first, SpeechResult.cancelled);

      final second = player.speak('다음 문장');
      final secondId = transport.requests.last;
      expect(secondId, isNot(firstId));
      transport.emit(firstId, SpeechTransportEventType.started);
      transport.emit(firstId, SpeechTransportEventType.completed);
      transport.emit(firstId, SpeechTransportEventType.error);
      expect(player.playback.value.phase, SpeechPhase.preparing);
      expect(player.playback.value.requestId, secondId);

      transport.emit(secondId, SpeechTransportEventType.started);
      expect(await second, SpeechResult.started);
      transport.emit(firstId, SpeechTransportEventType.cancelled);
      expect(player.playback.value.phase, SpeechPhase.playing);
      transport.emit(secondId, SpeechTransportEventType.completed);
      expect(player.playback.value.phase, SpeechPhase.ready);
    },
  );

  test(
    'watchdog cancels preparation even while the transport future is pending',
    () async {
      await player.dispose();
      final accepted = Completer<bool>();
      final transport = _TaggedTransport(acceptance: accepted.future);
      player = DeviceSpeechPlayer(
        transport: transport,
        preparationTimeout: const Duration(milliseconds: 100),
      );
      final outcome = player.speak('같이 가요');
      final requestId = transport.requests.single;
      expect(await outcome, SpeechResult.unavailable);
      expect(transport.stopCount, 1);
      expect(player.playback.value.phase, SpeechPhase.ready);

      transport.emit(requestId, SpeechTransportEventType.started);
      accepted.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(player.playback.value.phase, SpeechPhase.ready);
      expect(player.playback.value.result, SpeechResult.unavailable);
    },
  );
}

class _CallWaiter {
  final String method;
  final int occurrence;
  final done = Completer<void>();
  _CallWaiter(this.method, this.occurrence);
}

class _TaggedTransport implements SpeechTransport {
  final Future<bool>? acceptance;
  final requests = <int>[];
  int stopCount = 0;
  SpeechTransportListener? listener;

  _TaggedTransport({this.acceptance});

  @override
  set onEvent(SpeechTransportListener? value) => listener = value;

  @override
  Future<bool> speak(String text, {required int requestId, bool slow = false}) {
    requests.add(requestId);
    return acceptance ?? Future.value(true);
  }

  void emit(int requestId, SpeechTransportEventType type) =>
      listener?.call(SpeechTransportEvent(requestId, type));

  @override
  Future<void> stop() async => stopCount++;

  @override
  Future<void> dispose() async => listener = null;
}
