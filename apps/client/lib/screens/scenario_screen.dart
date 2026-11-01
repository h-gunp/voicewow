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
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: blue,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.graphic_eq, color: Colors.white, size: 23),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'VoiceMate',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      const SizedBox(height: 38),
      const Text(
        '모드 선택',
        style: TextStyle(
          color: blue,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        '사용할 모드를\n선택한다.',
        style: TextStyle(
          fontSize: 29,
          fontWeight: FontWeight.w800,
          height: 1.4,
          letterSpacing: -1,
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        '상황을 고른 뒤 마이크 입력을 확인한다.',
        style: TextStyle(color: muted, fontSize: 14, height: 1.7),
      ),
      const SizedBox(height: 28),
      LayoutBuilder(
        builder: (context, box) {
          final single = MediaQuery.textScalerOf(context).scale(14) > 20;
          final width = single ? box.maxWidth : (box.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: Scenario.values
                .where((s) => s.id == 'quiet' || s.id == 'meeting')
                .map((s) => SizedBox(width: width, child: _card(s)))
                .toList(),
          );
        },
      ),
      const SizedBox(height: 26),
      const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.phone_android_outlined, color: muted, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '휴대폰을 앞쪽 책상에 두고 사용한다.',
              style: TextStyle(color: muted, fontSize: 13, height: 1.6),
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('start'),
        onPressed: session.scenario == null ? null : onStart,
        child: const Text(
          '입력 확인 시작',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      const SizedBox(height: 15),
      const Center(
        child: Text(
          '시작할 때 마이크 권한을 확인한다.\n음성은 저장하거나 전송하지 않는다.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 12, height: 1.7),
        ),
      ),
    ],
  );
  Widget _card(Scenario s) {
    final selected = session.scenario == s;
    final icon = switch (s.id) {
      'quiet' => Icons.chat_bubble_outline,
      'noisy' => Icons.hearing_outlined,
      'meeting' => Icons.groups_outlined,
      _ => Icons.co_present_outlined,
    };
    return Semantics(
      button: true,
      selected: selected,
      label: '${s.title}, ${s.subtitle}',
      excludeSemantics: true,
      onTap: () => session.selectScenario(s),
      child: Material(
        color: selected ? wash : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected ? blue : line,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('scenario-${s.id}'),
          onTap: () => session.selectScenario(s),
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 118),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: selected ? blue : muted, size: 30),
                      const Spacer(),
                      if (selected)
                        const Icon(Icons.check_circle, color: blue, size: 19),
                    ],
                  ),
                  const SizedBox(height: 23),
                  Text(
                    s.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s.subtitle,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 12,
                      height: 1.6,
                    ),
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
