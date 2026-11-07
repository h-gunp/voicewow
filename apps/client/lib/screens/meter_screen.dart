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
      CaptureState.requesting when session.reason == 'context_resuming' =>
        '마이크 연결 후 오디오 엔진을 시작하고 있다.',
      CaptureState.requesting =>
        session.settings['noiseReductionState'] == 'loading'
            ? '소음 억제를 준비하고 있다.'
            : '마이크 권한을 확인한다.',
      CaptureState.running => '입력을 확인하고 있다.',
      CaptureState.error => switch (session.reason) {
        'permission_denied' => '마이크 권한이 필요하다.',
        'device_missing' => '마이크를 찾지 못했다.',
        'device_busy' => '마이크를 사용할 수 없다.',
        'context_resume_timeout' => '오디오 엔진이 제때 시작되지 않았다.',
        'context_resume_failed' => '오디오 엔진을 시작하지 못했다.',
        'context_not_running' => '오디오 엔진이 실행 상태가 아니다.',
        'frame_timeout' => '오디오 프레임을 받지 못했다.',
        'input_muted' => '마이크 입력이 일시 중단됐다.',
        'input_ended' => '마이크 입력이 종료됐다.',
        'settings_unavailable' => '마이크 입력 설정을 읽지 못했다.',
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
        'disabled' => '소음 억제가 꺼져 발화 막대를 표시하지 않는다.',
        'unavailable' => '소음 억제를 사용할 수 없어 발화 막대를 표시하지 않는다.',
        _ => '주변 소리도 함께 반영된다.',
      },
      CaptureState.error => switch (session.reason) {
        'permission_denied' => '주소창의 사이트 권한에서 마이크를 허용한 뒤 다시 시작한다.',
        'device_missing' => '마이크 연결을 확인한 뒤 다시 시작한다.',
        'device_busy' => '다른 앱의 마이크 사용을 확인한다.',
        'noise_reduction_failed' => '소음 억제 중 문제가 발생했다. 다시 시작한다.',
        'context_resume_timeout' ||
        'context_resume_failed' ||
        'context_not_running' => '다시 시작을 눌러 오디오 엔진을 다시 시작한다.',
        'frame_timeout' => '오디오 엔진 상태와 연결을 확인한 뒤 다시 시작한다.',
        'input_muted' || 'input_ended' => '마이크 연결을 확인한 뒤 다시 시작한다.',
        'settings_unavailable' => '브라우저와 마이크 연결을 확인한 뒤 다시 시작한다.',
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
    final a = session.analysis;
    final range = session.effectiveRange;
    final voice = a['voiceDbfs'] as num?;
    final noise = a['noiseDbfs'] as num?;
    final settings = session.settings;
    final processingUnknown = [
      'autoGainControl',
      'noiseSuppression',
      'echoCancellation',
    ].any((key) => settings[key] != true && settings[key] != false);
    final analysisStatus = switch ((
      session.state,
      settings['noiseReductionState'],
      settings['vadStatus'],
      a['reason'],
      a['state'],
    )) {
      (CaptureState.requesting, _, _, _, _) => '환경 분석을 준비하고 있다.',
      (CaptureState.idle || CaptureState.error, _, _, _, _) => '환경 분석이 중지됐다.',
      (_, 'disabled', _, _, _) => '소음 억제가 꺼져 환경 분석을 보류했다.',
      (_, 'unavailable', _, _, _)
          when settings['noiseReductionReason'] == 'unsupported_sample_rate' =>
        '오디오 처리 주파수 ${settings['contextSampleRate'] ?? '확인 불가'} Hz는 소음 억제를 지원하지 않는다.',
      (_, 'unavailable', _, _, _)
          when settings['noiseReductionReason'] == 'load_timeout' =>
        '소음 억제 준비 시간이 초과됐다.',
      (_, 'unavailable', _, _, _)
          when settings['noiseReductionReason'] == 'load_failed' =>
        '소음 억제 파일을 불러오거나 준비하지 못했다.',
      (_, 'unavailable', _, _, _) => '이 브라우저에서 소음 억제를 준비하지 못했다.',
      (_, _, 'load_timeout', _, _) => '발화 판별 파일을 불러오는 시간이 초과됐다.',
      (_, _, 'load_failed', _, _) => '발화 판별 파일을 불러오지 못했다.',
      (_, _, 'init_failed', _, _) => '발화 판별기를 준비하지 못했다.',
      (_, _, 'runtime_failed', _, _) => '발화 판별 중 오류가 발생했다.',
      (_, _, _, 'vad_runtime_failed', _) => '발화 판별 중 오류가 발생했다.',
      (_, _, _, 'invalid_analysis', _) => '분석 신호를 확인하지 못했다.',
      (_, _, _, 'input_gap', _) => '입력 프레임이 끊겨 분석을 다시 준비한다.',
      (_, _, _, 'processing_settings', _) when processingUnknown =>
        '브라우저 처리 설정을 확인할 수 없어 환경 잡음 추정과 자동 범위를 보류했다.',
      (_, _, _, 'processing_settings', _) =>
        '브라우저 처리가 켜져 있어 환경 잡음 추정과 자동 범위를 보류했다.',
      (_, _, _, _, 'ready') when a['provenance'] == 'relative_input' =>
        '상대 입력 분석 중',
      (_, _, _, _, 'ready') => '환경 분석 중',
      (_, _, _, _, 'collecting') => '비발화 증거를 수집하고 있다.',
      (_, _, _, _, 'held') => '잡음 정보가 오래됐거나 불확실해 보류했다.',
      (_, _, _, _, 'unsupported') => '자동 조절 지원 범위를 초과했다.',
      _ => '환경 분석 신호를 기다리고 있다.',
    };
    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        SwitchListTile(
          key: const Key('toggle-noise-reduction'),
          contentPadding: EdgeInsets.zero,
          title: const Text(
            '주변 소음 억제',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            session.noiseReductionEnabled ? '켜짐' : '꺼짐',
            style: const TextStyle(color: muted, fontSize: 14),
          ),
          value: session.noiseReductionEnabled,
          onChanged: session.state == CaptureState.requesting
              ? null
              : session.setNoiseReductionEnabled,
        ),
        Text(
          analysisStatus,
          textAlign: TextAlign.left,
          style: const TextStyle(color: muted, fontSize: 14),
        ),
        if (a['provenance'] == 'relative_input')
          const Text(
            '실험적 상대 입력 기준 · 실제 음압 아님',
            textAlign: TextAlign.left,
            style: TextStyle(color: muted, fontSize: 14),
          ),
      ],
    );
    final measurement = TweenAnimationBuilder<double>(
      tween: Tween(end: range.lower - s.referenceLower),
      duration: MediaQuery.disableAnimationsOf(context) || !range.adjusted
          ? Duration.zero
          : const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        final visualLower = double.parse(
          (s.referenceLower + value).toStringAsFixed(1),
        );
        final visualUpper = double.parse(
          (s.referenceUpper + value).toStringAsFixed(1),
        );
        final plot = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '입력 수준 ${session.displayLevel?.toStringAsFixed(1) ?? '—'}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w500),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: VolumeGauge(
                  scenario: s,
                  displayLevel: session.displayLevel,
                  lower: visualLower,
                  upper: visualUpper,
                ),
              ),
            ),
            if (session.displayLevel != null || a['meterState'] != 'nonSpeech')
              Text(
                session.displayLevel != null
                    ? '발화로 판정된 입력이다. 다른 사람의 소리도 포함될 수 있다.'
                    : a['meterState'] == 'confirming'
                    ? '발화 판정을 연속 확인하고 있다.'
                    : '발화 판정이 없거나 확인할 수 없어 막대를 비웠다.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted, fontSize: 14, height: 1.7),
              ),
            if (a['reason'] == 'processing_settings' && !processingUnknown)
              Text(
                '전처리 적용 · 막대는 상대 참고값이다.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted, fontSize: 14, height: 1.7),
              ),
            const SizedBox(height: 12),
          ],
        );
        final stats = Semantics(
          liveRegion: true,
          child: Text(
            [
              if (a['state'] == 'ready') ...[
                '발화 판정 ${a['speech'] == 'speech'
                    ? '발화 감지'
                    : a['speech'] == 'nonSpeech'
                    ? '비발화'
                    : '불확실'}',
                if (a['provenance'] != 'relative_input') ...[
                  '주변 잡음 추정 ${noise?.toStringAsFixed(1) ?? '—'} dBFS',
                  '발화 수준 추정 ${voice == null ? '—' : (voice + SessionController.inputLevelOffset).clamp(0, 120).toStringAsFixed(1)}',
                ],
                '${a['provenance'] == 'relative_input' ? '상대 입력 참고범위' : '환경 적응 참고범위'} ${visualLower.toStringAsFixed(1)}–${visualUpper.toStringAsFixed(1)}',
              ],
              if (value == range.lower - s.referenceLower)
                if (session.displayLevel case final level?)
                  '참고 범위 비교 ${double.parse(level.toStringAsFixed(1)) < range.lower
                      ? '하한 미만'
                      : double.parse(level.toStringAsFixed(1)) > range.upper
                      ? '상한 초과'
                      : '범위 안'} · 척도 정합성 미검증',
            ].join('\n'),
            textAlign: TextAlign.left,
            style: const TextStyle(color: muted, fontSize: 14, height: 1.7),
          ),
        );
        return LayoutBuilder(
          builder: (context, box) {
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [controls, const SizedBox(height: 12), stats],
            );
            if (box.maxWidth >= 640 &&
                MediaQuery.textScalerOf(context).scale(14) <= 20) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: plot),
                  const SizedBox(width: 40),
                  Expanded(flex: 5, child: details),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [plot, const SizedBox(height: 24), details],
            );
          },
        );
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: onBack,
              tooltip: '상황 선택으로 이동',
              icon: const Icon(Icons.arrow_back, size: 20),
            ),
            Expanded(
              child: Text(
                s.displayTitle,
                textAlign: TextAlign.left,
                style: sectionTitle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Semantics(
          liveRegion: true,
          child: Text(
            title,
            textAlign: TextAlign.left,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w600,
              height: 1.4,
              letterSpacing: -.7,
            ),
          ),
        ),
        const SizedBox(height: 9),
        Text(
          description,
          textAlign: TextAlign.left,
          style: const TextStyle(color: muted, fontSize: 14, height: 1.7),
        ),
        const SizedBox(height: 28),
        measurement,
        const SizedBox(height: 24),
        const Divider(),
        TextButton(
          onPressed: onBack,
          child: const Text('상황 변경', style: TextStyle(color: muted)),
        ),
        TextButton(
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
                        builder: (context, _) => diagnostics(context),
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

  Widget diagnostics(BuildContext context) {
    final a = session.analysis;
    final settings = session.settings;
    final contextLabel = switch (settings['contextState']) {
      'running' => '실행 중',
      'suspended' => '일시 중지',
      'interrupted' => '중단됨',
      'closed' => '종료됨',
      _ => '확인 불가',
    };
    final frameStatus = session.state != CaptureState.running
        ? '입력 상태 ${session.state.name}'
        : session.level == null
        ? '입력 프레임을 기다리고 있다.'
        : '입력 프레임 수신: ${session.frameCount} · ${settings['noiseReductionState'] == 'active' ? '소음 억제 후' : '브라우저 입력'} ${session.level!.dbfs?.toStringAsFixed(1) ?? '디지털 무음'}${session.level!.dbfs == null ? '' : ' dBFS'}';
    String flag(String key) => settings[key] == true
        ? '켜짐'
        : settings[key] == false
        ? '꺼짐'
        : '확인 불가';
    final vadLabel = a['reason'] == 'vad_runtime_failed'
        ? '실행 오류'
        : switch (settings['vadStatus']) {
            'ready' => '준비됨',
            'load_timeout' => '파일 시간 초과',
            'load_failed' => '파일 로드 실패',
            'init_failed' => '초기화 실패',
            'runtime_failed' => '실행 오류',
            _ => '확인 불가',
          };
    final processingUnknown = [
      'autoGainControl',
      'noiseSuppression',
      'echoCancellation',
    ].any((key) => settings[key] != true && settings[key] != false);
    final analysisStatus = switch ((
      session.state,
      settings['noiseReductionState'],
      settings['vadStatus'],
      a['reason'],
      a['state'],
    )) {
      (CaptureState.requesting, _, _, _, _) => '환경 분석을 준비하고 있다.',
      (CaptureState.idle || CaptureState.error, _, _, _, _) => '환경 분석이 중지됐다.',
      (_, 'disabled', _, _, _) => '소음 억제가 꺼져 환경 분석을 보류했다.',
      (_, 'unavailable', _, _, _)
          when settings['noiseReductionReason'] == 'unsupported_sample_rate' =>
        '오디오 처리 주파수 ${settings['contextSampleRate'] ?? '확인 불가'} Hz는 소음 억제를 지원하지 않는다.',
      (_, 'unavailable', _, _, _)
          when settings['noiseReductionReason'] == 'load_timeout' =>
        '소음 억제 준비 시간이 초과됐다.',
      (_, 'unavailable', _, _, _)
          when settings['noiseReductionReason'] == 'load_failed' =>
        '소음 억제 파일을 불러오거나 준비하지 못했다.',
      (_, 'unavailable', _, _, _) => '이 브라우저에서 소음 억제를 준비하지 못했다.',
      (_, _, 'load_timeout', _, _) => '발화 판별 파일을 불러오는 시간이 초과됐다.',
      (_, _, 'load_failed', _, _) => '발화 판별 파일을 불러오지 못했다.',
      (_, _, 'init_failed', _, _) => '발화 판별기를 준비하지 못했다.',
      (_, _, 'runtime_failed', _, _) => '발화 판별 중 오류가 발생했다.',
      (_, _, _, 'vad_runtime_failed', _) => '발화 판별 중 오류가 발생했다.',
      (_, _, _, 'invalid_analysis', _) => '분석 신호를 확인하지 못했다.',
      (_, _, _, 'input_gap', _) => '입력 프레임이 끊겨 분석을 다시 준비한다.',
      (_, _, _, 'processing_settings', _) when processingUnknown =>
        '브라우저 처리 설정을 확인할 수 없어 환경 잡음 추정과 자동 범위를 보류했다.',
      (_, _, _, 'processing_settings', _) =>
        '브라우저 처리가 켜져 있어 환경 잡음 추정과 자동 범위를 보류했다.',
      (_, _, _, _, 'ready') when a['provenance'] == 'relative_input' =>
        '상대 입력 분석 중',
      (_, _, _, _, 'ready') => '환경 분석 중',
      (_, _, _, _, 'collecting') => '비발화 증거를 수집하고 있다.',
      (_, _, _, _, 'held') => '잡음 정보가 오래됐거나 불확실해 보류했다.',
      (_, _, _, _, 'unsupported') => '자동 조절 지원 범위를 초과했다.',
      _ => '환경 분석 신호를 기다리고 있다.',
    };
    final inputLabel =
        session.state == CaptureState.running &&
            session.settings['noiseReductionState'] == 'active'
        ? '소음 억제 후 입력'
        : '원본 입력';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            '$frameStatus\n오디오 엔진 $contextLabel · 처리 주파수 ${settings['contextSampleRate'] ?? '확인 불가'} Hz\n$analysisStatus\n발화 판별기 $vadLabel\n자동 이득 ${flag('autoGainControl')} · 잡음 억제 ${flag('noiseSuppression')} · 반향 제거 ${flag('echoCancellation')}',
            textAlign: TextAlign.left,
            style: const TextStyle(color: muted, fontSize: 14, height: 1.7),
          ),
        ),
        if (a['provenance'] == 'relative_input')
          const Text(
            '상대 입력 추정은 브라우저 자동 이득 변화와 실제 소음 변화를 구분할 수 없다.',
            style: TextStyle(fontSize: 14, color: muted, height: 1.8),
          ),
        TextButton.icon(
          onPressed: () =>
              showLicensePage(context: context, applicationName: 'VoiceMate'),
          icon: const Icon(Icons.description_outlined),
          label: const Text('오픈소스 · 모델 이용 조건'),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '$inputLabel ${session.level?.dbfs?.toStringAsFixed(1) ?? '—'} dBFS\n수신 프레임 ${session.frameCount}\n입력 상태 ${session.state.name}\n${_settingsText()}',
            style: const TextStyle(fontSize: 14, color: muted, height: 1.8),
          ),
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
