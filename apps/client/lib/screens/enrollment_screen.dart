import 'package:flutter/material.dart';
import '../audio/audio_port.dart';
import '../session_controller.dart';
import 'meter_screen.dart';

class EnrollmentScreen extends StatelessWidget {
  final SessionController session;
  final VoidCallback onDone;
  const EnrollmentScreen({
    super.key,
    required this.session,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final state = session.enrollmentComplete
        ? 'registered'
        : session.speaker['state'];
    final ready =
        session.state == CaptureState.running &&
        session.settings['speakerAvailable'] == true &&
        session.settings['noiseReductionState'] == 'active' &&
        session.settings['vadStatus'] == 'ready';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '목소리 등록',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        const Text(
          '혼자 자연스럽게 말한다. 등록에는 소음 억제가 필요하므로 마이크 준비 시 켠다. 모델 약 26.5MB를 준비한다. 음성은 기기에서 처리하며 등록 정보는 새로고침하면 삭제된다. 화자 확인은 실험 기능이다.',
        ),
        const SizedBox(height: 20),
        Text(
          session.state == CaptureState.requesting
              ? '마이크와 소음 억제를 준비하고 있다.'
              : session.state == CaptureState.error
              ? '마이크를 준비하지 못했다: ${session.reason ?? "오류"}'
              : state == 'registered'
              ? '등록 완료 · 3/3'
              : state == 'quality'
              ? '음성 품질이 부족하다. 계속 말한다. · ${session.speaker['samples'] ?? 0}/3'
              : state == 'loading'
              ? '음성 모델을 준비하고 있다.'
              : state == 'unavailable'
              ? '화자 모델을 준비하지 못했다. 다시 시도한다.'
              : state == 'registering'
              ? '모델 준비 및 음성 수집 · ${session.speaker['samples'] ?? 0}/3'
              : session.state == CaptureState.running && !ready
              ? '소음 억제와 발화 감지를 준비하지 못했다.'
              : '마이크를 준비한 뒤 등록한다.',
          key: const Key('enrollment-status'),
        ),
        const SizedBox(height: 20),
        if (session.state != CaptureState.running)
          FilledButton(
            key: const Key('enrollment-start'),
            onPressed: session.state == CaptureState.requesting
                ? null
                : () => session.start(enrollment: true),
            child: const Text('마이크 준비'),
          ),
        if (session.state == CaptureState.requesting)
          TextButton(
            key: const Key('enrollment-cancel-request'),
            onPressed: session.stop,
            child: const Text('마이크 요청 취소'),
          ),
        if (session.state == CaptureState.running && state != 'registered')
          FilledButton(
            key: const Key('enrollment-record'),
            onPressed:
                ready &&
                    state != 'registering' &&
                    state != 'loading' &&
                    state != 'quality'
                ? session.beginSpeakerEnrollment
                : null,
            child: Text(state == 'unavailable' ? '다시 시도' : '등록 시작'),
          ),
        if (session.state == CaptureState.running && state != 'registered')
          TextButton(
            key: const Key('enrollment-cancel'),
            onPressed: () async {
              await session.deleteSpeaker();
              await session.stop();
            },
            child: const Text('등록 취소'),
          ),
        if (session.state == CaptureState.running && !ready)
          TextButton(
            key: const Key('enrollment-retry-setup'),
            onPressed: () async {
              final stopping = session.stop();
              final starting = session.start(enrollment: true);
              await Future.wait([stopping, starting]);
            },
            child: const Text('마이크 준비 다시 시도'),
          ),
        if (state == 'registered')
          FilledButton(
            key: const Key('enrollment-continue'),
            onPressed: onDone,
            child: const Text('계속'),
          ),
        TextButton(
          key: const Key('enrollment-skip'),
          onPressed: onDone,
          child: const Text('나중에 등록'),
        ),
        TextButton(
          key: const Key('enrollment-info'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('앱 정보 · 진단')),
                body: SafeArea(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ListenableBuilder(
                        listenable: session,
                        builder: (context, _) => MeterScreen(
                          session: session,
                          onBack: () {},
                        ).diagnostics(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          child: const Text('앱 정보 · 진단'),
        ),
      ],
    );
  }
}
