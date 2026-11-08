import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:voicemate/audio/audio_port.dart';
import 'package:voicemate/audio/native_audio_port.dart';
import 'package:voicemate/scenario.dart';
import 'package:voicemate/session_controller.dart';

const channel = MethodChannel('voicemate/volume');
const codec = StandardMethodCodec();

Future<void> nativeEvent(String method, Map<String, Object?> value) async {
  final done = Completer<void>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(MethodCall(method, value)),
        (_) => done.complete(),
      );
  await done.future;
}

Map<String, Object?> frame(int seq) => {
  'seq': seq,
  'power': 0.0001,
  'clipped': false,
  'speech': 'speech',
  'meterRms': 0.01,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecordPlatform previous;
  late PermissionPlatform permissions;
  late NativeAudioPort port;
  late SessionController session;
  late List<MethodCall> calls;
  late int ticket;
  Completer<Map<String, Object?>>? startGate;
  Completer<void>? stopGate;
  Completer<int>? boundaryGate;
  bool stopFails = false;

  setUp(() {
    previous = RecordPlatform.instance;
    permissions = PermissionPlatform();
    RecordPlatform.instance = permissions;
    calls = [];
    ticket = 0;
    startGate = null;
    stopGate = null;
    boundaryGate = null;
    stopFails = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'start':
              ticket = (call.arguments as Map)['session'] as int;
              return startGate?.future ??
                  {
                    'sampleRate': 48000,
                    'channelCount': 1,
                    'noiseReductionState': 'active',
                    'vadStatus': 'ready',
                  };
            case 'stop':
              await stopGate?.future;
              if (stopFails) throw PlatformException(code: 'device_busy');
              return null;
            case 'sampleBoundary':
              return boundaryGate?.future ?? -1;
          }
          throw StateError(call.method);
        });
    port = NativeAudioPort();
    session = SessionController(port)..selectScenario(Scenario.values.first);
  });

  tearDown(() async {
    stopGate?.complete();
    stopGate = null;
    session.dispose();
    await port.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    RecordPlatform.instance = previous;
  });

  test(
    'real native analysis contract drives meter and enables environment',
    () async {
      await session.start();
      expect(session.state, CaptureState.running);
      expect(session.canSampleEnvironment, isTrue);
      expect(session.settings.containsKey('autoGainControl'), isFalse);
      await nativeEvent('frames', {
        'session': ticket,
        'frames': [frame(0), frame(1), frame(2)],
      });
      expect(session.displayLevel, closeTo(74, 0.001));
      await session.stop();
      await nativeEvent('frames', {
        'session': ticket,
        'frames': [frame(3)],
      });
      expect(session.state, CaptureState.idle);
      expect(session.displayLevel, isNull);
    },
  );

  test(
    'permission denial is recoverable without opening native capture',
    () async {
      permissions.allowed = false;
      await session.start();
      expect(session.reason, 'permission_denied');
      expect(calls.where((call) => call.method == 'start'), isEmpty);
      permissions.allowed = true;
      await session.start();
      expect(session.state, CaptureState.running);
    },
  );

  test('cancel during permission prevents a late microphone start', () async {
    permissions.gate = Completer<bool>();
    final starting = session.start();
    await permissions.requested.future;
    await session.stop();
    permissions.gate!.complete(true);
    await starting;
    expect(calls.where((call) => call.method == 'start'), isEmpty);
    expect(session.state, CaptureState.idle);
  });

  test('late native start result cannot revive a stopped capture', () async {
    startGate = Completer<Map<String, Object?>>();
    final starting = session.start();
    while (ticket == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    await session.stop();
    startGate!.complete({
      'noiseReductionState': 'active',
      'vadStatus': 'ready',
    });
    await starting;
    expect(session.state, CaptureState.idle);
    expect(session.canSampleEnvironment, isFalse);
  });

  test('restart drains old stop and rejects old session callbacks', () async {
    await session.start();
    final old = ticket;
    stopGate = Completer<void>();
    final stopping = session.stop();
    final starting = session.start();
    await Future<void>.delayed(Duration.zero);
    expect(ticket, old);
    stopGate!.complete();
    stopGate = null;
    await stopping;
    await starting;
    expect(ticket, isNot(old));
    await nativeEvent('state', {
      'session': old,
      'state': 'error',
      'reason': 'input_ended',
    });
    expect(session.state, CaptureState.running);
  });

  test('sampling excludes frames queued before the native boundary', () async {
    await session.start();
    boundaryGate = Completer<int>();
    final sampling = session.sampleEnvironment();
    await nativeEvent('frames', {
      'session': ticket,
      'frames': [frame(0), frame(1)],
    });
    expect(session.environmentCollecting, isTrue);
    expect(session.environmentProgress, 0);
    boundaryGate!.complete(3);
    await sampling;
    await nativeEvent('frames', {
      'session': ticket,
      'frames': [frame(2), frame(3), frame(4)],
    });
    expect(session.environmentProgress, closeTo(1 / 500, 0.00001));
  });

  test(
    'cancel during sampling barrier never starts collection later',
    () async {
      await session.start();
      boundaryGate = Completer<int>();
      final sampling = session.sampleEnvironment();
      await session.cancelEnvironment();
      boundaryGate!.complete(8);
      await sampling;
      await nativeEvent('frames', {
        'session': ticket,
        'frames': [frame(9)],
      });
      expect(session.environmentCollecting, isFalse);
    },
  );

  test('stale input clears the meter then releases capture', () async {
    await session.start();
    await nativeEvent('frames', {
      'session': ticket,
      'frames': [frame(0), frame(1), frame(2)],
    });
    expect(session.displayLevel, isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(session.displayLevel, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 1700));
    expect(session.state, CaptureState.error);
    expect(session.reason, 'frame_timeout');
    expect(calls.any((call) => call.method == 'stop'), isTrue);
  });

  test(
    'malformed native frames stop capture instead of displaying invalid values',
    () async {
      await session.start();
      await nativeEvent('frames', {
        'session': ticket,
        'frames': [
          {...frame(0), 'power': double.nan},
        ],
      });
      expect(session.state, CaptureState.error);
      expect(session.reason, 'invalid_samples');
    },
  );

  test('failed cleanup is retried before a new microphone opens', () async {
    await session.start();
    final old = ticket;
    stopFails = true;
    await session.stop();
    expect(session.state, CaptureState.idle);
    stopFails = false;
    await session.start();
    expect(session.state, CaptureState.running);
    expect(
      calls
          .where(
            (call) =>
                call.method == 'stop' &&
                (call.arguments as Map)['session'] == old,
          )
          .length,
      2,
    );
  });

  test(
    'duplicates and level-only batches do not preserve a stale speech meter',
    () async {
      await session.start();
      final speech = {
        'session': ticket,
        'frames': [frame(0), frame(1), frame(2)],
      };
      await nativeEvent('frames', speech);
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await nativeEvent('frames', speech);
        await nativeEvent('frames', {
          'session': ticket,
          'frames': [],
          'level': {
            'rms': 0.01,
            'peak': 0.02,
            'dbfs': -40.0,
            'normalized': 0.5,
            'sampleCount': 4800,
          },
        });
      }
      expect(session.displayLevel, isNull);
    },
  );
}

class PermissionPlatform extends RecordPlatform {
  bool allowed = true;
  Completer<bool>? gate;
  final requested = Completer<void>();
  @override
  Future<void> create(String recorderId) async {}
  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async {
    if (!requested.isCompleted) requested.complete();
    return gate?.future ?? allowed;
  }

  @override
  Future<void> dispose(String recorderId) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
