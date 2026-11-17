import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import '../app_theme.dart';
import '../scenario.dart';
import '../session_controller.dart';

class ScenarioScreen extends StatelessWidget {
  final SessionController session;
  final VoidCallback onStart;
  const ScenarioScreen({
    super.key,
    required this.session,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        '음량 측정',
        style: TextStyle(
          color: accent,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: .4,
        ),
      ),
      const SizedBox(height: 14),
      const Text('내 목소리를\n눈으로 확인한다.', style: pageTitle),
      const SizedBox(height: 12),
      const Text('상황을 고른 뒤 마이크 입력을 확인한다.', style: bodyCopy),
      const SizedBox(height: 28),
      const Text('모드 선택', style: sectionTitle),
      const SizedBox(height: 14),
      for (final s in Scenario.values.where(
        (s) => s.id == 'quiet' || s.id == 'meeting',
      ))
        Padding(padding: const EdgeInsets.only(bottom: 14), child: _option(s)),
      const SizedBox(height: 20),
      const Text('휴대폰을 앞쪽 책상에 두고 사용한다.', style: smallCopy),
      const SizedBox(height: 32),
      FilledButton.icon(
        key: const Key('start'),
        onPressed: session.scenario == null ? null : onStart,
        icon: const Icon(CupertinoIcons.mic, size: 20),
        label: const Text('입력 확인 시작'),
      ),
      const SizedBox(height: 16),
      const Text('시작할 때 마이크 권한을 확인한다.\n음성은 저장하거나 전송하지 않는다.', style: smallCopy),
    ],
  );

  Widget _option(Scenario s) {
    final selected = session.scenario == s;
    return Semantics(
      button: true,
      selected: selected,
      label: '${s.title}, ${s.subtitle}',
      excludeSemantics: true,
      onTap: () => session.selectScenario(s),
      child: GlassSurface(
        tint: selected ? wash : null,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: Key('scenario-${s.id}'),
            onTap: () => session.selectScenario(s),
            borderRadius: BorderRadius.circular(21),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selected ? accent : wash,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Icon(
                      s.id == 'quiet'
                          ? CupertinoIcons.chat_bubble_2
                          : CupertinoIcons.person_2,
                      color: selected ? Colors.white : accent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          s.id == 'quiet'
                              ? '가까운 사람과 편하게 대화한다.'
                              : '여러 사람에게 내용을 전한다.',
                          style: smallCopy,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    selected
                        ? CupertinoIcons.checkmark_circle_fill
                        : CupertinoIcons.circle,
                    color: selected ? accent : muted,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
