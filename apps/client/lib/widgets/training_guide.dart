import 'package:flutter/material.dart';
import '../app_theme.dart';

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
    child: const Text('어깨의 힘을 빼고 편하게 호흡하며 기다린다.', style: bodyCopy),
  );
}

class TrainingGuideScreen extends StatelessWidget {
  final ValueChanged<int> onSelectSection;
  const TrainingGuideScreen({super.key, required this.onSelectSection});

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
                const Text('기능별 사용 방법', style: pageTitle),
                const SizedBox(height: 8),
                _feature(
                  0,
                  '음량 측정',
                  '상황 선택 → 입력 확인 시작 → 주변 환경음 듣기 → 말하며 막대 확인 순서로 사용한다. 환경음을 들을 때는 잠시 말을 멈춘다. 장소가 바뀌면 환경음을 다시 듣는다.',
                ),
                _feature(
                  1,
                  '발음 훈련',
                  '워밍업을 마친 뒤 단어나 문장을 선택한다. 마이크 버튼을 눌러 읽고 다시 눌러 녹음을 끝내면 비교 결과를 볼 수 있다.\n초록색은 일치, 빨간색과 밑줄은 차이, 회색은 판단이 불확실한 부분이다.\n처음에는 약 356MB 모델을 내려받는다.',
                ),
                _feature(
                  2,
                  '높낮이 연습',
                  '워밍업을 마친 뒤 준비된 문구를 선택한다. 가이드를 확인하고 녹음한 뒤 내 목소리와 그래프를 비교한다. 내 대본으로도 연습할 수 있다.',
                ),
                const SizedBox(height: 16),
                const Text(
                  '화면 위의 ‘글자 크기’에서 크기를 바꿀 수 있다. 선택은 이 기기의 브라우저에 저장된다.',
                  style: bodyCopy,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _feature(int index, String title, String body) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: sectionTitle),
        const SizedBox(height: 8),
        Text(body, style: bodyCopy),
        const SizedBox(height: 12),
        OutlinedButton(
          key: Key('guide-open-$index'),
          onPressed: () => onSelectSection(index),
          child: Text('$title 시작'),
        ),
      ],
    ),
  );
}
