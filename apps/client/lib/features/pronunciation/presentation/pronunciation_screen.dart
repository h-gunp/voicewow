import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app_theme.dart';
import '../data/learning_store.dart';
import '../data/speech_player.dart';
import '../data/pronunciation_recorder.dart';
import '../domain/quiz_catalog.dart';
import '../domain/pronunciation_guide.dart';
import 'quiz_training_view.dart';
import 'speech_controls.dart';
import 'pronunciation_practice_view.dart';

class PronunciationScreen extends StatefulWidget {
  final LearningController? learning;
  final SpeechPlayer? speech;
  final PronunciationRecorder? recorder;
  final bool suspended;
  const PronunciationScreen({
    super.key,
    this.learning,
    this.speech,
    this.recorder,
    this.suspended = false,
  });

  @override
  State<PronunciationScreen> createState() => _PronunciationScreenState();
}

class _PronunciationScreenState extends State<PronunciationScreen>
    with SingleTickerProviderStateMixin {
  late final LearningController learning;
  late final SpeechPlayer speech;
  late final SpeechPlaybackController playback;
  late final TabController tabs;
  late final PronunciationRecorder recorder;
  _PracticeTarget? _target;
  int _practiceRequest = 0;
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
    speech = widget.speech ?? DeviceSpeechPlayer(localOnly: true);
    recorder = widget.recorder ?? createPronunciationRecorder();
    playback = SpeechPlaybackController(speech);
    tabs = TabController(length: 3, vsync: this)..addListener(_tabChanged);
    unawaited(learning.load());
  }

  void _tabChanged() {
    if (tabs.index == _tab) return;
    ++_practiceRequest;
    unawaited(_stopSpeech());
    unawaited(recorder.cancel());
    setState(() => _tab = tabs.index);
  }

  @override
  void didUpdateWidget(covariant PronunciationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.suspended && !oldWidget.suspended) {
      ++_practiceRequest;
      unawaited(_stopSpeech());
    }
  }

  void _openGuide(String value) {
    if (value.runes.length > PronunciationGuideEngine.maxInputLength ||
        !RegExp('[가-힣]').hasMatch(value)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('완성된 한글이 포함된 300자 이내 문장으로 연습할 수 있다.')),
      );
      return;
    }
    final guide = const PronunciationGuideEngine().analyze(value);
    _requestedGuide = value;
    _guideRequest++;
    unawaited(
      _openPractice(
        _PracticeTarget(
          value,
          pronunciationReferences(value, guide.pronunciation),
          approximate: true,
          note: '기본 발음 규칙을 적용한 참고 읽기다.',
        ),
      ),
    );
  }

  void _openItem(QuizItem item) => unawaited(
    _openPractice(
      _PracticeTarget(
        item.text,
        pronunciationReferences(item.text, item.pronunciation),
        id: item.id,
        note: item.explanation,
      ),
    ),
  );

  Future<void> _openPractice(_PracticeTarget target) async {
    final ticket = ++_practiceRequest;
    await _stopSpeech();
    await recorder.cancel();
    if (mounted && ticket == _practiceRequest) setState(() => _target = target);
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
    ++_practiceRequest;
    tabs.dispose();
    playback.dispose();
    if (widget.learning == null) learning.dispose();
    unawaited(speech.stop());
    if (widget.speech == null) unawaited(speech.dispose());
    if (widget.recorder == null) {
      unawaited(recorder.dispose());
    } else {
      unawaited(recorder.cancel());
    }
    super.dispose();
  }

  Future<void> _stopSpeech() async {
    await playback.stop();
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    if (target == null) return _buildLibrary(context);
    return ListenableBuilder(
      listenable: learning,
      builder: (context, _) => PronunciationPracticeView(
        key: ValueKey('practice-${target.id ?? target.text}'),
        text: target.text,
        references: target.references,
        referenceIsApproximate: target.approximate,
        referenceNote: target.note,
        recorder: recorder,
        suspended: widget.suspended,
        playback: playback,
        bookmarked:
            target.id != null && learning.bookmarkedIds.contains(target.id),
        onBookmark: target.id == null
            ? null
            : () => unawaited(learning.toggleBookmark(target.id!)),
        onExit: () async {
          if (mounted) setState(() => _target = null);
        },
      ),
    );
  }

  Widget _buildLibrary(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (constraints.maxHeight >=
                  MediaQuery.textScalerOf(context).scale(280)) ...[
                const SizedBox(height: 22),
                const Text(
                  '내 속도로, 함께',
                  style: TextStyle(
                    color: blue,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                const Text('발음 훈련', style: pageTitle),
                const SizedBox(height: 6),
                const Text('익숙한 말부터, 내 속도로 연습해요.', style: smallCopy),
                const SizedBox(height: 18),
              ],
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: canvas,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: line),
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
                    color: wash,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: line),
                  ),
                  tabs: [
                    Tab(height: _tabHeight(context), text: '발음 연습'),
                    Tab(height: _tabHeight(context), text: '내 문장'),
                    Tab(height: _tabHeight(context), text: '복습'),
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
                                onPractice: _openItem,
                                active: _tab == 0,
                              ),
                              _PersonalGuideView(
                                learning: learning,
                                playback: playback,
                                onStop: _stopSpeech,
                                onOpenSaved: _openSavedGuides,
                                requestedGuide: _requestedGuide,
                                guideRequest: _guideRequest,
                                onPractice: _openGuide,
                              ),
                              QuizTrainingView(
                                learning: learning,
                                onPractice: _openItem,
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
    ),
  );

  double _tabHeight(BuildContext context) =>
      (MediaQuery.textScalerOf(context).scale(14) * 1.6 + 16).clamp(
        48,
        double.infinity,
      );
}

class _PracticeTarget {
  const _PracticeTarget(
    this.text,
    this.references, {
    this.id,
    this.note,
    this.approximate = false,
  });
  final String text;
  final List<String> references;
  final String? id, note;
  final bool approximate;
}

class _PersonalGuideView extends StatefulWidget {
  final LearningController learning;
  final SpeechPlaybackController playback;
  final Future<void> Function() onStop;
  final VoidCallback onOpenSaved;
  final String? requestedGuide;
  final int guideRequest;
  final ValueChanged<String> onPractice;
  const _PersonalGuideView({
    required this.learning,
    required this.playback,
    required this.onStop,
    required this.onOpenSaved,
    required this.requestedGuide,
    required this.guideRequest,
    required this.onPractice,
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
          const Text('내 문장 발음 가이드', style: sectionTitle),
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
                borderRadius: BorderRadius.circular(6),
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
                borderRadius: BorderRadius.circular(6),
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
                        fontWeight: FontWeight.w700,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('괄호 안은 소리 내어 읽을 때 참고하는 표기예요.'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('guide-practice'),
                    onPressed: () => widget.onPractice(guide.original),
                    icon: const Icon(Icons.mic),
                    label: const Text('이 문장 발음 연습'),
                  ),
                  const SizedBox(height: 10),
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
            const Text('발음 포인트', style: sectionTitle),
            const SizedBox(height: 10),
            if (guide.points.isEmpty)
              const Text('적용된 발음 변화가 없어요. 위의 읽는 소리를 참고해 연습해 보세요.'),
            for (final point in guide.points)
              Card(
                color: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: const BorderSide(color: line),
                ),
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
