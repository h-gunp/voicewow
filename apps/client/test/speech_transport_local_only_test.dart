import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/features/pronunciation/data/speech_transport_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late List<Map<String, Object>> voices;
  setUp(() {
    calls = [];
    voices = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'isLanguageAvailable') return true;
      if (call.method == 'getVoices') return voices;
      if (call.method == 'speak') return 0;
      return 1;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'local pronunciation refuses network and uninstalled Korean voices',
    () async {
      voices = [
        {'name': 'network', 'locale': 'ko-KR', 'network_required': '1'},
        {
          'name': 'missing',
          'locale': 'ko-KR',
          'network_required': '0',
          'features': 'notInstalled',
        },
      ];
      final speech = NativeSpeechTransport(localOnly: true);
      expect(await speech.speak('연습', requestId: 1), isFalse);
      expect(calls.where((call) => call.method == 'speak'), isEmpty);
      await speech.dispose();
    },
  );

  test(
    'local pronunciation explicitly selects installed offline voice',
    () async {
      voices = [
        {'name': 'network', 'locale': 'ko-KR', 'network_required': '1'},
        {'name': 'local', 'locale': 'ko-KR', 'network_required': '0'},
      ];
      final speech = NativeSpeechTransport(localOnly: true);
      await speech.speak('연습', requestId: 2);
      expect(calls.singleWhere((call) => call.method == 'setVoice').arguments, {
        'name': 'local',
        'locale': 'ko-KR',
      });
      expect(calls.where((call) => call.method == 'speak'), hasLength(1));
      await speech.dispose();
    },
  );
}
