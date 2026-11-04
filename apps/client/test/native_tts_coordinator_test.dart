import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/shared/native_tts_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'synthesis cancellation remains quarantined until its terminal event',
    () async {
      final coordinator = NativeTtsCoordinator();
      final synth = (await coordinator.acquire(NativeTtsKind.synthesis))!;
      synth.issued = true;
      expect(
        await coordinator.acquire(NativeTtsKind.speech, timeout: Duration.zero),
        isNull,
      );
      expect(synth.isCurrent, isTrue);
      await coordinator.dispatch(const MethodCall('speak.onCancel'));
      final speech = await coordinator.acquire(
        NativeTtsKind.speech,
        timeout: Duration.zero,
      );
      expect(speech, isNotNull);
      speech!.releaseUnissued();
    },
  );

  test(
    'retired speech blocks synthesis until its own terminal event',
    () async {
      final coordinator = NativeTtsCoordinator();
      final speech = (await coordinator.acquire(NativeTtsKind.speech))!;
      speech.issued = true;
      expect(
        await coordinator.acquire(
          NativeTtsKind.synthesis,
          timeout: Duration.zero,
        ),
        isNull,
      );
      await coordinator.dispatch(const MethodCall('speak.onCancel'));
      final synth = await coordinator.acquire(
        NativeTtsKind.synthesis,
        timeout: Duration.zero,
      );
      expect(synth, isNotNull);
      synth!.releaseUnissued();
    },
  );
}
