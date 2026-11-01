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
        Semantics(
          liveRegion: true,
          child: Text(
            '$frameStatus\n오디오 엔진 $contextLabel · 처리 주파수 ${settings['contextSampleRate'] ?? '확인 불가'} Hz\n$analysisStatus\n발화 판별기 $vadLabel\n자동 이득 ${flag('autoGainControl')} · 잡음 억제 ${flag('noiseSuppression')} · 반향 제거 ${flag('echoCancellation')}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, fontSize: 12, height: 1.7),
          ),
        ),
        VolumeGauge(
          scenario: s,
          displayLevel: session.displayLevel,
          lower: range.lower,
          upper: range.upper,
        ),
        Text(
          '입력 수준 ${session.displayLevel?.toStringAsFixed(1) ?? '—'}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const Text(
          '상대 입력 막대 · 본인 목소리로 확인된 음량이 아니다.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 12, height: 1.7),
        ),
        Text(
          session.settings['speakerAvailable'] == true
              ? '화자 확인은 실험 기능이다. 등록 시 모델 약 26.5 MB를 내려받는다. 음성은 기기에서 처리하며 등록 정보는 이 페이지의 메모리에만 둔다. 새로고침하면 삭제된다. 다른 사람·재생음이 섞일 수 있다.'
              : session.settings['speakerAvailable'] == false
              ? '현재 공개 버전에서는 화자 등록을 제공하지 않음'
              : '화자 등록 제공 여부를 확인 중이다.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, fontSize: 12, height: 1.7),
        ),
        TextButton(
          key: const Key('speaker-model-notice'),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('화자 모델 및 라이선스'),
              content: const SingleChildScrollView(
                child: SelectableText(
                  'WeSpeaker contributors의 VoxCeleb ResNet34 ONNX 모델을 변경 없이 사용한다.\n\n'
                  'WeSpeaker 공식 모델 문서는 VoxCeleb 모델에 CC BY 4.0을 명시한다. 원본 Hugging Face README 메타데이터는 license: apache-2.0을 명시한다. 모델은 보증 없이 제공되며 제작자가 이 프로젝트를 보증한다는 뜻이 아니다.\n\n'
                  '모델 출처: https://huggingface.co/Wespeaker/wespeaker-voxceleb-resnet34/blob/ff1ac5bca8ef11e90662b879aa923979e0bd277b/voxceleb_resnet34.onnx\n\n'
                  'CC BY 4.0: https://creativecommons.org/licenses/by/4.0/legalcode.en\n\n'
                  '전체 고지와 Apache 원문 및 ONNX Runtime 고지: audio/vendor/speaker/MODEL-NOTICE.txt',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('닫기'),
                ),
              ],
            ),
          ),
          child: const Text('모델 및 라이선스'),
        ),
        Text(
          _speakerStatus(),
          key: const Key('speaker-status'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, fontSize: 12, height: 1.7),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            OutlinedButton(
              key: const Key('begin-speaker-enrollment'),
              onPressed:
                  session.state == CaptureState.running &&
                      session.settings['speakerAvailable'] == true
                  ? session.beginSpeakerEnrollment
                  : null,
              child: const Text('내 목소리 등록'),
            ),
            TextButton(
              key: const Key('delete-speaker'),
              onPressed: session.deleteSpeaker,
              child: const Text('등록 삭제'),
            ),
          ],
        ),
        Text(
          session.displayLevel != null
              ? '발화로 판정된 입력이다. 다른 사람의 소리도 포함될 수 있다.'
              : a['meterState'] == 'confirming'
              ? '발화 판정을 연속 확인하고 있다.'
              : a['meterState'] == 'nonSpeech'
              ? '발화가 감지되지 않아 막대를 비웠다.'
              : '발화 판정이 없거나 확인할 수 없어 막대를 비웠다.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, fontSize: 12, height: 1.7),
        ),
        if (a['reason'] == 'processing_settings')
          Text(
            processingUnknown
                ? '전처리 미확인 · 막대는 상대 참고값이다.'
                : '전처리 적용 · 막대는 상대 참고값이다.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, fontSize: 12, height: 1.7),
          ),
        const SizedBox(height: 5),
        const Text(
          '빨간 선은 참고 범위의 하한·상한이다.\n참고 척도 · 실제 데시벨은 아니다.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 12, height: 1.7),
        ),
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text(
            [
              if (a['state'] == 'ready') ...[
                '발화 판정 ${a['speech'] == 'speech'
                    ? '발화 감지'
                    : a['speech'] == 'nonSpeech'
                    ? '비발화'
                    : '불확실'}',
                '주변 잡음 추정 ${noise?.toStringAsFixed(1) ?? '—'} dBFS',
                '발화 수준 추정 ${voice == null ? '—' : (voice + SessionController.inputLevelOffset).clamp(0, 120).toStringAsFixed(1)}',
                '환경 적응 참고범위 ${range.lower.toStringAsFixed(1)}–${range.upper.toStringAsFixed(1)}',
              ],
              if (!range.adjusted) '환경 적응 보류 · 기본 참고범위',
              if (session.displayLevel case final level?)
                '참고 범위 비교 ${double.parse(level.toStringAsFixed(1)) < range.lower
                    ? '하한 미만'
                    : double.parse(level.toStringAsFixed(1)) > range.upper
                    ? '상한 초과'
                    : '범위 안'} · 척도 정합성 미검증',
              '실험적 환경 추정 · 화자 확인과 별개이며 실제 음압이 아니다.',
            ].join('\n'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, fontSize: 12, height: 1.7),
          ),
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

  String _speakerStatus() {
    final data = session.speaker;
    final state = data['state'];
    if (state == 'similar' || state == 'dissimilar' || state == 'uncertain') {
      final start = data['startTime'],
          end = data['endTime'],
          delay = data['delayMs'];
      if (start is! num ||
          end is! num ||
          delay is! num ||
          !start.isFinite ||
          !end.isFinite ||
          !delay.isFinite)
        return '화자 확인 보류';
      final label = state == 'similar'
          ? '등록 음성과 유사'
          : state == 'dissimilar'
          ? '등록 음성과 불일치'
          : '화자 불확실';
      return '$label · 실험 결과\n오디오 시간 ${start.toStringAsFixed(2)}–${end.toStringAsFixed(2)}초 · 지연 ${delay.toStringAsFixed(0)}ms';
    }
    return switch (state) {
      'registering' => '화자 등록 중 · ${data['samples'] ?? 0}/3',
      'registered' => '화자 등록 완료 · 발화 확인 대기',
      'confirming' => '화자 확인 대기',
      'quality' => '음성 품질 부족 · 다시 말한다',
      'unavailable' => '화자 확인 준비되지 않음 · 사용할 수 없다',
      _ => '화자 확인 준비되지 않음 · 등록되지 않음',
    };
  }
}
