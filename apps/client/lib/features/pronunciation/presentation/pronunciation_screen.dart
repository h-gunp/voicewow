import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app_theme.dart';
import '../data/learning_store.dart';
import '../data/speech_player.dart';
import '../domain/pronunciation_guide.dart';
import 'quiz_training_view.dart';
import 'speech_controls.dart';

class PronunciationScreen extends StatefulWidget {
  final LearningController? learning;
  final SpeechPlayer? speech;
  const PronunciationScreen({super.key, this.learning, this.speech});

  @override
  State<PronunciationScreen> createState() => _PronunciationScreenState();
}

class _PronunciationScreenState extends State<PronunciationScreen>
    with SingleTickerProviderStateMixin {
  late final LearningController learning;
  late final SpeechPlayer speech;
  late final SpeechPlaybackController playback;
  late final TabController tabs;
  int _speechEpoch = 0;
  int _tab = 0;
  String? _requestedGuide;
  int _guideRequest = 0;
  int _reviewRequest = 0;
  ReviewFilter _reviewInitialFilter = ReviewFilter.all;

  @override
  void initState() {
    super.initState();
    learning =
        widget.learning ?? LearningController(PreferencesLearningStore());
    speech = widget.speech ?? DeviceSpeechPlayer();
    playback = SpeechPlaybackController(speech);
    tabs = TabController(length: 3, vsync: this)..addListener(_tabChanged);
    unawaited(learning.load());
  }

  void _tabChanged() {
    if (tabs.index == _tab) return;
    unawaited(_stopSpeech());
    setState(() => _tab = tabs.index);
  }

  void _openGuide(String value) {
    unawaited(_stopSpeech());
    setState(() {
      _requestedGuide = value;
      _guideRequest++;
    });
    tabs.animateTo(1);
  }

  void _openSavedGuides() {
    unawaited(_stopSpeech());
    setState(() {
      _reviewInitialFilter = ReviewFilter.guides;
      _reviewRequest++;
    });
    tabs.animateTo(2);
  }

  @override
  void dispose() {
    tabs.dispose();
    playback.dispose();
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
    await playback.stop();
  }

  @override
  Widget build(BuildContext context) => Center(
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
                controller: tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: ink,
                unselectedLabelColor: muted,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xffa9cecc)),
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
                          controller: tabs,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            QuizTrainingView(
                              learning: learning,
                              onSpeak: _speak,
                              onStop: _stopSpeech,
                              playback: playback,
                              active: _tab == 0,
                            ),
                            _PersonalGuideView(
                              learning: learning,
                              playback: playback,
                              onStop: _stopSpeech,
                              onOpenSaved: _openSavedGuides,
                              requestedGuide: _requestedGuide,
                              guideRequest: _guideRequest,
                            ),
                            QuizTrainingView(
                              learning: learning,
                              onSpeak: _speak,
                              onStop: _stopSpeech,
                              playback: playback,
                              reviewOnly: true,
                              active: _tab == 2,
                              onOpenGuide: _openGuide,
                              reviewInitialFilter: _reviewInitialFilter,
                              reviewFilterRequest: _reviewRequest,
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
  );
}

class _PersonalGuideView extends StatefulWidget {
  final LearningController learning;
  final SpeechPlaybackController playback;
  final Future<void> Function() onStop;
  final VoidCallback onOpenSaved;
  final String? requestedGuide;
  final int guideRequest;
  const _PersonalGuideView({
    required this.learning,
    required this.playback,
    required this.onStop,
    required this.onOpenSaved,
    required this.requestedGuide,
    required this.guideRequest,
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
  final Object _speechOwner = Object();

  @override
  void initState() {
    super.initState();
    _loadRequestedGuide();
  }

  @override
  void didUpdateWidget(covariant _PersonalGuideView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.guideRequest != widget.guideRequest) {
      _loadRequestedGuide();
      _scrollToInput();
    }
  }

  void _loadRequestedGuide() {
    final value = widget.requestedGuide;
    if (value == null) return;
    text.text = value;
    _updateAnalysis();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    unawaited(widget.playback.stop(owner: _speechOwner));
    text.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _analyze() {
    FocusScope.of(context).unfocus();
    unawaited(widget.onStop());
    setState(_updateAnalysis);
  }

  void _updateAnalysis() {
    final input = text.text.trim();
    if (input.isEmpty) {
      result = null;
      error = '연습할 문장을 입력해 주세요.';
      return;
    }
    try {
      final next = engine.analyze(input);
      error = next.hasHangul ? null : '한글이 포함된 문장을 입력해 주세요.';
      result = next.hasHangul ? next : null;
    } on ArgumentError {
      result = null;
      error = '문장은 300자 이내로 입력해 주세요.';
    }
  }

  void _fill(String value) {
    text.text = value;
    _analyze();
    _scrollToInput();
  }

  void _scrollToInput() {
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
          const Text(
            '예시 문장 · 눌러서 체험해 보세요',
            style: TextStyle(color: muted, fontSize: 14),
          ),
          const SizedBox(height: 6),
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
                  SpeechControls(
                    playback: widget.playback,
                    text: guide.original,
                    owner: _speechOwner,
                    normalKey: const Key('guide-speak'),
                    slowKey: const Key('guide-speak-slow'),
                    normalLabel: '예시 음성 듣기',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('guide-save'),
                    onPressed: () async {
                      await widget.learning.saveGuide(guide.original);
                      if (context.mounted &&
                          !widget.learning.storageUnavailable) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('복습의 ‘저장한 내 문장’에 저장했어요.'),
                          ),
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
              const Text('적용된 발음 변화가 없어요. 위의 읽는 소리를 참고해 연습해 보세요.'),
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
          OutlinedButton.icon(
            key: const Key('guide-open-saved'),
            onPressed: widget.onOpenSaved,
            icon: const Icon(Icons.bookmarks_outlined),
            label: Text('저장한 문장 보기 · ${widget.learning.guides.length}개'),
          ),
          const SizedBox(height: 8),
          const Text(
            '저장한 내 문장은 복습에서 다시 연습할 수 있어요.',
            style: TextStyle(color: muted),
          ),
        ],
      ),
    );
  }
}
