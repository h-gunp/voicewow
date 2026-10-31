import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../audio/audio_port.dart';
import '../session_controller.dart';
import '../widgets/volume_gauge.dart';

class MeterScreen extends StatelessWidget {
  final SessionController session;
  final VoidCallback onBack;
  const MeterScreen({super.key, required this.session, required this.onBack});
  String get title {
    return switch (session.state) {
      CaptureState.requesting =>
        session.settings['noiseReductionState'] == 'loading'
            ? '소음 억제를 준비하고 있다.'
            : '마이크 권한을 확인한다.',
      CaptureState.running => '입력을 확인하고 있다.',
      CaptureState.error => switch (session.reason) {
        'permission_denied' => '마이크 권한이 필요하다.',
        'device_missing' => '마이크를 찾지 못했다.',
        'device_busy' => '마이크를 사용할 수 없다.',
        _ => '지금은 입력이 끊겼다.',
      },
      CaptureState.idle => '입력이 중지됐다.',
    };
  }

  String get description {
    if (session.reason == 'tab_hidden') return '탭을 벗어나 입력을 중지했다. 다시 시작한다.';
    if (session.reason == 'device_changed') return '입력 장치 구성이 바뀌었다. 다시 시작한다.';
    return switch (session.state) {
      CaptureState.requesting =>
        session.settings['noiseReductionState'] == 'loading'
            ? '입력 준비가 끝나면 측정을 시작한다.'
            : '브라우저의 권한 요청에서 마이크를 허용한다.',
      CaptureState.running => switch (session.settings['noiseReductionState']) {
        'active' => '주변 소음을 줄인 입력이다. 다른 사람의 목소리가 남을 수 있다.',
        'disabled' => '소음 억제를 끄고 원본 입력을 표시한다.',
        'unavailable' => '소음 억제를 사용할 수 없어 원본 입력을 표시한다.',
        _ => '주변 소리도 함께 반영된다.',
      },
      CaptureState.error => switch (session.reason) {
        'permission_denied' => '주소창의 사이트 권한에서 마이크를 허용한 뒤 다시 시작한다.',
        'device_missing' => '마이크 연결을 확인한 뒤 다시 시작한다.',
        'device_busy' => '다른 앱의 마이크 사용을 확인한다.',
        'noise_reduction_failed' => '소음 억제 중 문제가 발생했다. 다시 시작한다.',
        'insecure_context' => '마이크를 사용하려면 이 페이지를 HTTPS 주소로 연다.',
        'unsupported' =>
          '이 브라우저에서는 필요한 입력 기능을 지원하지 않는다. HTTPS 페이지를 최신 Safari 또는 Chrome에서 연다.',
        _ => '마이크 연결과 브라우저 상태를 확인한 뒤 다시 시작한다.',
      },
      CaptureState.idle => '다시 시작하면 마이크 입력을 확인할 수 있다.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = session.scenario!;
    final inputLabel =
        session.state == CaptureState.running &&
            session.settings['noiseReductionState'] == 'active'
        ? '소음 억제 후 입력'
        : '원본 입력';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: onBack,
              tooltip: '상황 선택으로 이동',
              icon: const Icon(Icons.arrow_back_ios_new, size: 19),
            ),
            Expanded(
              child: Text(
                s.displayTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 40),
          ],
        ),
        const SizedBox(height: 26),
        Semantics(
          liveRegion: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              height: 1.4,
              letterSpacing: -.7,
            ),
          ),
        ),
        const SizedBox(height: 9),
        Text(
          description,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, fontSize: 13, height: 1.7),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          key: const Key('toggle-noise-reduction'),
          contentPadding: EdgeInsets.zero,
          title: const Text(
            '주변 소음 억제',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            session.noiseReductionEnabled ? '켜짐' : '꺼짐',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          value: session.noiseReductionEnabled,
          onChanged: session.state == CaptureState.requesting
              ? null
              : session.setNoiseReductionEnabled,
        ),
        VolumeGauge(scenario: s, displayLevel: session.displayLevel),
        Text(
          '입력 수준 ${session.displayLevel?.toStringAsFixed(1) ?? '—'}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        const Text(
          '빨간 선은 선택한 상황의 하한·상한이다.\n참고 척도 · 실제 데시벨은 아니다.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 12, height: 1.7),
        ),
        const SizedBox(height: 28),
        OutlinedButton(
          key: const Key('toggle-capture'),
          onPressed: session.active ? session.stop : session.start,
          child: Text(
            session.state == CaptureState.requesting
                ? '요청 취소'
                : session.active
                ? '입력 중지'
                : '다시 시작',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onBack,
          child: const Text('상황 변경', style: TextStyle(color: muted)),
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text(
            '입력 정보',
            style: TextStyle(fontSize: 12, color: muted),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '$inputLabel ${session.level?.dbfs?.toStringAsFixed(1) ?? '—'} dBFS\n수신 프레임 ${session.frameCount}\n입력 상태 ${session.state.name}\n${_settingsText()}',
                style: const TextStyle(fontSize: 12, color: muted, height: 1.8),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _settingsText() {
    final settings = session.settings;
    final noiseReduction = switch ((
      session.state,
      settings['noiseReductionState'],
    )) {
      (CaptureState.requesting, 'loading') => '준비 중',
      (CaptureState.running, 'active') => '적용 중',
      (CaptureState.running, 'disabled') => '꺼짐',
      (CaptureState.running, 'unavailable') => '사용 불가',
      (CaptureState.idle || CaptureState.error, _) => '미사용',
      _ => '확인 불가',
    };
    String flag(String key) => settings[key] == true
        ? '켜짐'
        : settings[key] == false
        ? '꺼짐'
        : '확인 불가';
    return '앱 소음 억제 $noiseReduction\n오디오 처리 ${settings['contextSampleRate'] ?? '—'} Hz\n자동 이득 ${flag('autoGainControl')} · 브라우저 잡음 억제 ${flag('noiseSuppression')}\n반향 제거 ${flag('echoCancellation')}';
  }
}
