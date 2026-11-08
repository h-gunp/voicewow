import 'package:flutter/material.dart';
import '../app_theme.dart';

const _restNote = '목이 아프거나 목소리가 쉬면 쉬어 간다. 치료사에게 받은 개인별 안내가 있으면 그 안내를 따른다.';

/// Short, microphone-free preparation while the practice screen loads.
class TrainingPreparationCard extends StatelessWidget {
  const TrainingPreparationCard({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: wash,
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(6),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('기다리는 동안 가볍게 준비', style: sectionTitle),
        SizedBox(height: 12),
        Text('어깨의 힘을 빼고 편하게 숨을 쉰다. 숨을 억지로 깊게 쉬거나 오래 참지 않는다.', style: bodyCopy),
        SizedBox(height: 12),
        Text(_restNote, style: smallCopy),
      ],
    ),
  );
}

class TrainingGuideScreen extends StatefulWidget {
  final ValueChanged<int> onSelectSection;
  const TrainingGuideScreen({super.key, required this.onSelectSection});

  @override
  State<TrainingGuideScreen> createState() => _TrainingGuideScreenState();
}

class _TrainingGuideScreenState extends State<TrainingGuideScreen> {
  int _step = 0;
  static const _steps = [
    ('편한 자세', '편하게 앉거나 서서 어깨의 힘을 가볍게 뺀다. 목을 누르거나 주무르지 않아도 된다.'),
    ('편한 호흡', '코로 편하게 들이마시고 입으로 부드럽게 내쉰다. 숨을 억지로 깊게 쉬거나 오래 참지 않는다.'),
    (
      '짧게 말하기',
      '편한 목소리로 짧은 말을 한 번 해 본다. 예를 들면 “안녕”처럼 익숙한 말이면 된다. 소리를 크게 내거나 오래 이어 가지 않는다.',
    ),
    (
      '훈련 고르기',
      '처음이라면 음량 확인으로 시작하고, 짧은 단어나 문장의 발음을 연습한 뒤 높낮이를 살펴볼 수 있다. 원하는 기능부터 시작해도 된다.',
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('사용 안내')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('어디서부터 시작할까', style: pageTitle),
                const SizedBox(height: 12),
                const Text(
                  '준비 → 호흡 → 짧게 말하기 → 훈련 선택\n정해진 시간 없이 편한 속도로 따라가면 된다. 이 안내에서는 마이크를 켜지 않는다.',
                  style: bodyCopy,
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: wash,
                    border: Border.all(color: line),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          '${_step + 1} / 4 · ${_steps[_step].$1}',
                          style: sectionTitle,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(_steps[_step].$2, style: bodyCopy),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          OutlinedButton(
                            key: const Key('preparation-previous'),
                            onPressed: _step == 0
                                ? null
                                : () => setState(() => _step--),
                            child: const Text('이전'),
                          ),
                          if (_step < _steps.length - 1)
                            FilledButton(
                              key: const Key('preparation-next'),
                              onPressed: () => setState(() => _step++),
                              child: const Text('다음'),
                            ),
                        ],
                      ),
                      if (_step < _steps.length - 1)
                        TextButton(
                          key: const Key('preparation-skip'),
                          onPressed: () =>
                              setState(() => _step = _steps.length - 1),
                          child: const Text('준비 건너뛰기'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(_restNote, style: bodyCopy),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                const Text('기능별 사용 방법', style: sectionTitle),
                const SizedBox(height: 8),
                _feature(
                  0,
                  '1. 음량 측정',
                  '목소리 크기 살펴보기',
                  '상황 선택 → 입력 확인 시작 → 주변 환경음 듣기 → 말하며 막대 확인 순서로 사용한다. 환경음을 들을 때는 잠시 말을 멈춘다. 장소가 바뀌면 환경음을 다시 듣는다.\n표시값과 참고 범위는 연습용이며, 보정된 소음계 수치는 아니다.',
                ),
                _feature(
                  1,
                  '2. 발음 훈련',
                  '짧은 단어부터 읽어 보기',
                  '단어나 문장을 선택하고 발음 모델을 준비한다. 마이크 버튼을 눌러 읽은 뒤 다시 눌러 녹음을 끝내면 비교 결과를 볼 수 있다.\n초록색은 추정 일치, 빨간색과 밑줄은 차이, 회색은 판단이 불확실한 부분이다. 인식 결과는 실제 발음과 다를 수 있다.\n처음에는 약 356MB 모델을 내려받는다. 녹음은 기기 안에서 분석한다.',
                ),
                _feature(
                  2,
                  '3. 높낮이 연습',
                  '한 문장의 흐름 살펴보기',
                  '처음에는 준비된 문구를 선택한다. 가이드를 확인하고 녹음한 뒤 내 목소리와 그래프를 비교한다. 내 대본으로도 연습할 수 있다.\n기기용 음성 모델을 처음 준비할 때는 시간이 걸릴 수 있다. 높낮이가 예시와 다르다고 발음이 틀렸다는 뜻은 아니다.',
                ),
                const SizedBox(height: 16),
                const Text(
                  '화면 위의 ‘글자 크기’에서 크기를 바꿀 수 있다. 선택은 이 기기의 브라우저에 저장된다.',
                  style: bodyCopy,
                ),
                const SizedBox(height: 16),
                const ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('준비 안내의 근거'),
                  children: [
                    SelectableText(
                      '일반적인 호흡·목소리 관리 자료를 참고한 안내다. 개인별 치료 순서나 효과를 검증한 프로그램은 아니다.\n\nNHS · 편한 호흡\nhttps://www.nhs.uk/mental-health/self-help/guides-tools-and-activities/breathing-exercises-for-stress/\n\nNIDCD · 목소리 관리\nhttps://www.nidcd.nih.gov/health/taking-care-your-voice\n\nASHA · 음성장애 안내\nhttps://www.asha.org/practice-portal/clinical-topics/voice-disorders/',
                      style: smallCopy,
                    ),
                    SizedBox(height: 16),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _feature(int index, String title, String subtitle, String body) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: sectionTitle),
            const SizedBox(height: 8),
            Text(subtitle, style: bodyCopy),
            const SizedBox(height: 8),
            Text(body, style: bodyCopy),
            const SizedBox(height: 12),
            OutlinedButton(
              key: Key('guide-open-$index'),
              onPressed: () => widget.onSelectSection(index),
              child: Text('${title.substring(3)} 시작'),
            ),
          ],
        ),
      );
}
