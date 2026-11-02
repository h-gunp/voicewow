import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/features/pronunciation/data/speech_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late DeviceSpeechPlayer player;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall) platform;

  Future<void> event(String method, [Object? arguments]) async {
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall(method, arguments)),
      null,
    );
  }

  setUp(() {
    calls = [];
    platform = (call) async => call.method == 'isLanguageAvailable' ? true : 1;
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return platform(call);
    });
    player = DeviceSpeechPlayer();
  });

  tearDown(() async {
    await player.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'native success acknowledgement starts speech without a callback',
    () async {
      expect(await player.speak('같이 가요'), SpeechResult.started);
      expect(
        calls
            .singleWhere((call) => call.method == 'isLanguageAvailable')
            .arguments,
        'ko-KR',
      );
      expect(
        calls.singleWhere((call) => call.method == 'setLanguage').arguments,
        'ko-KR',
      );
      final spoken = calls
          .singleWhere((call) => call.method == 'speak')
          .arguments;
      // The plugin sends a map on Android and the text itself on other hosts.
      expect(spoken is Map ? spoken['text'] : spoken, '같이 가요');
    },
  );

  test('slow practice uses a lower rate than ordinary speech', () async {
    expect(await player.speak('국물'), SpeechResult.started);
    expect(await player.speak('국물', slow: true), SpeechResult.started);
    final rates = calls
        .where((call) => call.method == 'setSpeechRate')
        .map((call) => call.arguments as double)
        .toList();
    expect(rates, hasLength(2));
    expect(rates.last, lessThan(rates.first));
    expect(rates.every((rate) => rate > 0), isTrue);
  });

  test('web null return waits for the actual start callback', () async {
    final invoked = Completer<void>();
    platform = (call) async {
      if (call.method == 'isLanguageAvailable') return true;
      if (call.method == 'speak') {
        invoked.complete();
        return null;
      }
      return 1;
    };
    final outcome = player.speak('같이 가요');
    var completed = false;
    unawaited(outcome.then((_) => completed = true));
    await invoked.future;
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);

    await event('speak.onStart');
    expect(await outcome, SpeechResult.started);
  });

  test(
    'a web error callback reports unavailable instead of successful initiation',
    () async {
      final invoked = Completer<void>();
      platform = (call) async {
        if (call.method == 'isLanguageAvailable') return true;
        if (call.method == 'speak') {
          invoked.complete();
          return null;
        }
        return 1;
      };
      final outcome = player.speak('같이 가요');
      await invoked.future;
      await event('speak.onError', 'language-unavailable');
      expect(await outcome, SpeechResult.unavailable);
    },
  );

  test('an unavailable Korean voice does not issue a speak command', () async {
    platform = (call) async => call.method == 'isLanguageAvailable' ? false : 1;
    expect(await player.speak('같이 가요'), SpeechResult.unavailable);
    expect(calls.where((call) => call.method == 'speak'), isEmpty);
  });

  test(
    'a rejected platform command is unavailable without waiting for an event',
    () async {
      platform = (call) async {
        if (call.method == 'isLanguageAvailable') return true;
        return call.method == 'speak' ? 0 : 1;
      };
      expect(await player.speak('같이 가요'), SpeechResult.unavailable);
    },
  );

  test(
    'a platform exception is unavailable and does not escape into the UI',
    () async {
      platform = (call) async {
        if (call.method == 'isLanguageAvailable') return true;
        if (call.method == 'speak') {
          throw PlatformException(code: 'voice-engine-unavailable');
        }
        return 1;
      };
      expect(await player.speak('같이 가요'), SpeechResult.unavailable);
    },
  );

  test(
    'stop during voice lookup cancels the request before it can speak',
    () async {
      final lookupStarted = Completer<void>();
      final available = Completer<bool>();
      platform = (call) async {
        if (call.method == 'isLanguageAvailable') {
          lookupStarted.complete();
          return available.future;
        }
        return 1;
      };
      final outcome = player.speak('같이 가요');
      await lookupStarted.future;
      await player.stop();
      available.complete(true);

      expect(await outcome, SpeechResult.cancelled);
      expect(calls.where((call) => call.method == 'speak'), isEmpty);
    },
  );

  test(
    'stop after a web request cancels its pending start confirmation',
    () async {
      final invoked = Completer<void>();
      platform = (call) async {
        if (call.method == 'isLanguageAvailable') return true;
        if (call.method == 'speak') {
          invoked.complete();
          return null;
        }
        return 1;
      };
      final outcome = player.speak('같이 가요');
      await invoked.future;
      await player.stop();

      expect(await outcome, SpeechResult.cancelled);
      // A late callback after cancellation must not resurrect the old request.
      await event('speak.onStart');
      expect(await outcome, SpeechResult.cancelled);
    },
  );

  test('disposing during voice lookup cancels pending speech', () async {
    final lookupStarted = Completer<void>();
    final available = Completer<bool>();
    platform = (call) async {
      if (call.method == 'isLanguageAvailable') {
        lookupStarted.complete();
        return available.future;
      }
      return 1;
    };
    final outcome = player.speak('같이 가요');
    await lookupStarted.future;
    await player.dispose();
    available.complete(true);

    expect(await outcome, SpeechResult.cancelled);
    expect(calls.where((call) => call.method == 'speak'), isEmpty);
  });
}
