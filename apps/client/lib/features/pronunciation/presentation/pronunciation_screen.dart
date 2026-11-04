import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app_theme.dart';
import '../data/learning_store.dart';
import '../data/speech_player.dart';
import '../domain/pronunciation_guide.dart';
import 'quiz_training_view.dart';

class PronunciationScreen extends StatefulWidget {
  final LearningController? learning;
  final SpeechPlayer? speech;
  const PronunciationScreen({super.key, this.learning, this.speech});

  @override
  State<PronunciationScreen> createState() => _PronunciationScreenState();
}

class _PronunciationScreenState extends State<PronunciationScreen> {
  late final LearningController learning;
  late final SpeechPlayer speech;
  int _speechEpoch = 0;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    learning =
        widget.learning ?? LearningController(PreferencesLearningStore());
    speech = widget.speech ?? DeviceSpeechPlayer();
    unawaited(learning.load());
  }

  @override
  void dispose() {
    if (widget.learning == null) learning.dispose();
    unawaited(speech.stop());
    if (widget.speech == null) unawaited(speech.dispose());
    super.dispose();
  }

  Future<void> _speak(String text, bool slow) async {
    final epoch = ++_speechEpoch;
    final outcome = await speech.speak(text, slow: slow);
    if (!mounted ||
        epoch != _speechEpoch ||
        outcome != SpeechResult.unavailable)
      return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('한국어 예시 음성을 재생할 수 없어요. 기기의 한국어 음성 설정을 확인해 주세요.'),
      ),
    );
  }

  Future<void> _stopSpeech() async {
    ++_speechEpoch;
    await speech.stop();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 22),
              const Text(
                '내 속도로, 함께',
                style: TextStyle(
                  color: Color(0xff146b70),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '발음 훈련',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                '익숙한 말부터, 내 속도로 연습해요.',
                style: TextStyle(color: muted, fontSize: 16),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .65),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white),
                ),
                child: TabBar(
                  onTap: (value) {
                    unawaited(_stopSpeech());
                    setState(() => _tab = value);
                  },
                  labelColor: ink,
                  unselectedLabelColor: muted,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xffcbd9ef)),
                  ),
                  tabs: const [
                    Tab(text: '발음 퀴즈'),
                    Tab(text: '내 문장'),
                    Tab(text: '복습'),
                  ],
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: learning,
                  builder: (context, _) {
                    if (!learning.ready) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return Column(
                      children: [
                        if (learning.storageUnavailable)
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text(
                              '기록을 저장하지 못했어요. 이번 연습은 계속할 수 있어요.',
                              style: TextStyle(color: red),
                            ),
                          ),
                        Expanded(
                          child: TabBarView(
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              QuizTrainingView(
                                learning: learning,
                                onSpeak: _speak,
                                onStop: _stopSpeech,
                                active: _tab == 0,
                              ),
                              _PersonalGuideView(
                                learning: learning,
                                onSpeak: _speak,
                                onStop: _stopSpeech,
                              ),
                              QuizTrainingView(
                                learning: learning,
                                onSpeak: _speak,
                                onStop: _stopSpeech,
                                reviewOnly: true,
                                active: _tab == 2,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PersonalGuideView extends StatefulWidget {
  final LearningController learning;
  final Future<void> Function(String, bool) onSpeak;
  final Future<void> Function() onStop;
  const _PersonalGuideView({
    required this.learning,
    required this.onSpeak,
    required this.onStop,
  });

  @override
  State<_PersonalGuideView> createState() => _PersonalGuideViewState();
}

class _PersonalGuideViewState extends State<_PersonalGuideView>
    with AutomaticKeepAliveClientMixin {
  final text = TextEditingController();
  final engine = const PronunciationGuideEngine();
  final scroll = ScrollController();
  GuideResult? result;
  String? error;
  bool slow = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    text.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _analyze() {
    FocusScope.of(context).unfocus();
    unawaited(widget.onStop());
    final input = text.text.trim();
    if (input.isEmpty) {
      setState(() => error = '연습할 문장을 입력해 주세요.');
      return;
    }
    try {
      final next = engine.analyze(input);
      setState(() {
        error = next.hasHangul ? null : '한글이 포함된 문장을 입력해 주세요.';
        result = next.hasHangul ? next : null;
      });
    } on ArgumentError {
      setState(() {
        result = null;
        error = '문장은 300자 이내로 입력해 주세요.';
      });
    }
  }

  void _fill(String value) {
    text.text = value;
    _analyze();
    if (scroll.hasClients) {
      if (MediaQuery.disableAnimationsOf(context)) {
        scroll.jumpTo(0);
      } else {
        scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final guide = result;
    return SingleChildScrollView(
      controller: scroll,
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '내 문장 발음 가이드',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text('어렵게 느껴지는 문장을 입력하고 읽는 소리를 확인해 보세요.'),
          const SizedBox(height: 20),
          TextField(
            key: const Key('guide-input'),
            controller: text,
            minLines: 2,
            maxLines: 5,
            maxLength: 300,
            decoration: InputDecoration(
              labelText: '연습할 문장',
              hintText: '예: 같이 가요',
              errorText: error,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onChanged: (_) {
              unawaited(widget.onStop());
              setState(() {
                result = null;
                error = null;
              });
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final sample in ['같이 가요', '국물이 뜨거워요', '책을 읽어요'])
                ActionChip(label: Text(sample), onPressed: () => _fill(sample)),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('guide-analyze'),
            onPressed: _analyze,
            icon: const Icon(Icons.auto_stories_outlined),
            label: const Text('발음 가이드 보기'),
          ),
          if (guide != null) ...[
            const SizedBox(height: 24),
            Container(
              key: const Key('guide-result'),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '읽는 소리 · 발음 참고',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      '[${guide.pronunciation}]',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('괄호 안은 소리 내어 읽을 때 참고하는 표기예요.'),
                  const SizedBox(height: 16),
                  Material(
                    color: Colors.transparent,
                    child: SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('천천히 듣기'),
                      value: slow,
                      onChanged: (value) => setState(() => slow = value),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => widget.onSpeak(guide.original, slow),
                    icon: const Icon(Icons.volume_up_outlined),
                    label: const Text('예시 음성 듣기'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('guide-save'),
                    onPressed: () async {
                      await widget.learning.saveGuide(guide.original);
                      if (context.mounted &&
                          !widget.learning.storageUnavailable) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('내 문장에 저장했어요.')),
                        );
                      }
                    },
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('내 문장에 저장'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '발음 포인트',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            if (guide.points.isEmpty)
              const Text('적용된 발음 변화가 없어요. 예시 음성을 들으며 연습해 보세요.'),
            for (final point in guide.points)
              Card(
                color: Colors.white,
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${point.before} → [${point.after}]',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 19,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(point.explanation),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            for (final note in guide.notes)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(note, style: const TextStyle(color: muted)),
              ),
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                '예시 음성은 기기의 한국어 음성으로 재생돼요.',
                style: TextStyle(color: muted, fontSize: 14),
              ),
            ),
          ],
          const SizedBox(height: 32),
          Text(
            '저장한 내 문장 · ${widget.learning.guides.length}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (widget.learning.guides.isEmpty)
            const Text(
              '다시 연습하고 싶은 문장을 저장해 보세요.',
              style: TextStyle(color: muted),
            ),
          for (final saved in widget.learning.guides)
            Card(
              elevation: 0,
              color: Colors.white,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                title: Text(saved.text),
                subtitle: const Text('눌러서 다시 연습하기'),
                onTap: () => _fill(saved.text),
                trailing: IconButton(
                  tooltip: '저장한 문장 삭제',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => widget.learning.deleteGuide(saved.text),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
