import 'package:flutter/material.dart';
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
      const Text('사용할 상황', style: smallCopy),
      const SizedBox(height: 8),
      const Text('모드 선택', style: pageTitle),
      const SizedBox(height: 12),
      const Text('상황을 고른 뒤 마이크 입력을 확인한다.', style: bodyCopy),
      const SizedBox(height: 32),
      const Divider(),
      for (final s in Scenario.values.where(
        (s) => s.id == 'quiet' || s.id == 'meeting',
      ))
        _option(s),
      const SizedBox(height: 20),
      const Text('휴대폰을 앞쪽 책상에 두고 사용한다.', style: smallCopy),
      const SizedBox(height: 32),
      FilledButton(
        key: const Key('start'),
        onPressed: session.scenario == null ? null : onStart,
        child: const Text('입력 확인 시작'),
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
      child: Material(
        color: selected ? wash : canvas,
        child: InkWell(
          key: Key('scenario-${s.id}'),
          onTap: () => session.selectScenario(s),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: line)),
            ),
            child: Row(
              children: [
                Icon(
                  s.id == 'quiet'
                      ? Icons.chat_bubble_outline
                      : Icons.groups_outlined,
                  color: selected ? accent : muted,
                  size: 24,
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
                      Text(s.subtitle, style: bodyCopy),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected ? accent : muted,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
