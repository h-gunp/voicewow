import 'package:flutter/material.dart';
import '../app_theme.dart';

class TrainingWarmup extends StatefulWidget {
  final String trainingName;
  final VoidCallback onComplete;

  const TrainingWarmup({
    super.key,
    required this.trainingName,
    required this.onComplete,
  });

  @override
  State<TrainingWarmup> createState() => _TrainingWarmupState();
}

class _TrainingWarmupState extends State<TrainingWarmup> {
  int _step = 0;
  static const _steps = [
    ('자세 풀기', '편하게 앉거나 선다. 어깨를 가볍게 내리고 턱과 목의 힘을 뺀다.', Icons.self_improvement),
    (
      '숨 들이마시기',
      '한 손을 배꼽 위에 얹는다. 코로 천천히 편하게 숨을 들이마시며 배가 부풀어 오르는 움직임을 느낀다.',
      Icons.expand,
    ),
    (
      '숨 내쉬기',
      '입으로 부드럽게 숨을 내쉬며 배가 들어가는 움직임을 느낀다. 편한 속도로 몇 번 반복한 뒤 훈련을 시작한다.',
      Icons.compress,
    ),
  ];

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: ValueKey(_step),
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (MediaQuery.textScalerOf(context).scale(16) < 28) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: wash,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    '${widget.trainingName} · 워밍업',
                    style: smallCopy.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            const Text('몸과 목을 편하게', style: pageTitle),
            if (MediaQuery.textScalerOf(context).scale(16) < 28) ...[
              const SizedBox(height: 12),
              const Text('가볍게 긴장을 풀고 호흡을 준비한다.', style: bodyCopy),
            ],
            const SizedBox(height: 28),
            Row(
              children: [
                for (var index = 0; index < _steps.length; index++)
                  Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(
                        right: index == _steps.length - 1 ? 0 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: index <= _step ? accent : line,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            GlassSurface(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ExcludeSemantics(
                    child: Center(
                      child: Container(
                        width: 144,
                        height: 144,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: wash.withValues(alpha: .55),
                          border: Border.all(color: Colors.white),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: .8),
                            border: Border.all(color: line),
                          ),
                          child: Icon(
                            _steps[_step].$3,
                            size: 48,
                            color: accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      '${_step + 1} / 3 · ${_steps[_step].$1}',
                      style: sectionTitle.copyWith(fontSize: 20),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(_steps[_step].$2, style: bodyCopy),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_step < _steps.length - 1)
              FilledButton(
                key: const Key('warmup-next'),
                onPressed: () => setState(() => _step++),
                child: const Text('다음'),
              )
            else
              FilledButton(
                key: const Key('warmup-start'),
                onPressed: widget.onComplete,
                child: Text('${widget.trainingName} 시작'),
              ),
            if (_step > 0)
              TextButton(
                key: const Key('warmup-previous'),
                onPressed: () => setState(() => _step--),
                child: const Text('이전'),
              ),
            TextButton(
              key: const Key('warmup-skip'),
              onPressed: widget.onComplete,
              child: const Text('건너뛰고 훈련 시작'),
            ),
          ],
        ),
      ),
    ),
  );
}
