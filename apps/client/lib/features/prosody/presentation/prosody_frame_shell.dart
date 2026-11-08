import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../widgets/training_guide.dart';

class ProsodyFrameShell extends StatelessWidget {
  const ProsodyFrameShell({
    super.key,
    required this.frame,
    required this.ready,
    required this.onRetry,
    this.issue,
  });

  final Widget frame;
  final bool ready;
  final String? issue;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      // Platform views must paint once to attach their DOM and finish loading.
      ExcludeSemantics(
        excluding: !ready,
        child: IgnorePointer(ignoring: !ready, child: frame),
      ),
      if (!ready)
        ColoredBox(
          color: canvas,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    issue ?? '높낮이 연습 화면을 준비 중이다.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 16),
                if (issue == null) const LinearProgressIndicator(),
                const SizedBox(height: 20),
                const TrainingPreparationCard(),
                if (issue != null) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('다시 불러오기'),
                  ),
                ],
              ],
            ),
          ),
        ),
    ],
  );
}
