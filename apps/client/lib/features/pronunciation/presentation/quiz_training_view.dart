import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../data/learning_store.dart';
import '../domain/quiz_catalog.dart';

class QuizTrainingView extends StatefulWidget {
  final LearningController learning;
  final Future<void> Function(String text, bool slow) onSpeak;
  final Future<void> Function()? onStop;
  final bool reviewOnly;
  final bool active;

  const QuizTrainingView({
    super.key,
    required this.learning,
    required this.onSpeak,
    this.onStop,
    this.reviewOnly = false,
    this.active = true,
  });

  @override
  State<QuizTrainingView> createState() => _QuizTrainingViewState();
}

enum _ReviewFilter { wrong, bookmarks, all }

class _QuizTrainingViewState extends State<QuizTrainingView> {
  final Random _random = Random();
  final Map<String, List<String>> _options = {};
  TrainingCategory? _category;
  String? _group;
  _ReviewFilter _reviewFilter = _ReviewFilter.wrong;
  List<QuizItem>? _session;
  final List<QuizItem> _sessionWrong = [];
  int _index = 0;
  int _correctCount = 0;
  int? _selected;
  bool _submitted = false;
  bool _summary = false;
  bool _speaking = false;
  int _speechEpoch = 0;

  void _stopVoice() {
    ++_speechEpoch;
    _speaking = false;
    final stopping = widget.onStop?.call();
    if (stopping != null) unawaited(stopping);
  }

  @override
  void dispose() {
    _stopVoice();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant QuizTrainingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) _stopVoice();
    if (oldWidget.reviewOnly != widget.reviewOnly) {
      _category = null;
      _group = null;
      _resetSession();
    }
  }

  void _resetSession() {
    _stopVoice();
    _session = null;
    _sessionWrong.clear();
    _options.clear();
    _index = 0;
    _correctCount = 0;
    _selected = null;
    _submitted = false;
    _summary = false;
  }

  void _startSession(List<QuizItem> items, {int startAt = 0}) {
    if (items.isEmpty || !widget.learning.ready) return;
    final ordered = [...items.skip(startAt), ...items.take(startAt)];
    setState(() {
      _resetSession();
      _session = ordered;
      for (final item in ordered) {
        _options[item.id] = [item.pronunciation, item.distractor]
          ..shuffle(_random);
      }
    });
  }

  void _submit() {
    if (_selected == null || _submitted || _session == null) return;
    final item = _session![_index];
    final correct = _options[item.id]![_selected!] == item.pronunciation;
    setState(() {
      _submitted = true;
      if (correct) {
        _correctCount++;
      } else {
        _sessionWrong.add(item);
      }
    });
    unawaited(widget.learning.recordAnswer(item.id, correct));
  }

  void _next() {
    if (!_submitted || _session == null) return;
    _stopVoice();
    setState(() {
      if (_index + 1 == _session!.length) {
        _summary = true;
      } else {
        _index++;
        _selected = null;
        _submitted = false;
      }
    });
  }

  Future<void> _speak(QuizItem item, bool slow) async {
    if (!_submitted || _speaking) return;
    final epoch = ++_speechEpoch;
    setState(() => _speaking = true);
    try {
      // Read the original text so the platform TTS can apply Korean prosody.
      await widget.onSpeak(item.text, slow);
    } catch (_) {
      if (mounted && epoch == _speechEpoch) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('음성을 재생하지 못했어요. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted && epoch == _speechEpoch) {
        setState(() => _speaking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.learning,
    builder: (context, _) {
      if (!widget.learning.ready) {
        return const Center(child: CircularProgressIndicator());
      }
      return PopScope<void>(
        canPop: !widget.active || (_session == null && _category == null),
        onPopInvokedWithResult: (didPop, result) {
          if (didPop || !widget.active) return;
          if (_session != null) {
            setState(_resetSession);
          } else if (_category != null) {
            setState(() {
              _category = null;
              _group = null;
            });
          }
        },
        child: SingleChildScrollView(
          key: ValueKey(
            _session != null
                ? 'quiz-scroll-${_summary ? 'summary' : _index}'
                : widget.reviewOnly
                ? 'review-${_reviewFilter.name}'
                : 'catalog-${_category?.name ?? 'home'}-${_group ?? 'all'}',
          ),
          padding: const EdgeInsets.fromLTRB(0, 24, 0, 36),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: _session != null
                  ? _summary
                        ? _buildSummary(context)
                        : _buildQuestion(context)
                  : widget.reviewOnly
                  ? _buildReview(context)
                  : _category != null
                  ? _buildCategory(context)
                  : _buildHub(context),
            ),
          ),
        ),
      );
    },
  );

  Widget _buildHub(BuildContext context) {
    final completed = quizCatalog
        .where((item) => widget.learning.answers.containsKey(item.id))
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Eyebrow('한 문장씩, 자신 있게'),
        const SizedBox(height: 10),
        Text('발음 구별 퀴즈', style: _heading(context)),
        const SizedBox(height: 10),
        const Text(
          '단어부터 일상과 업무의 문장까지.\n두 보기 중 올바른 읽는 소리를 골라 보세요.',
          style: TextStyle(color: muted, height: 1.65, fontSize: 15),
        ),
        const SizedBox(height: 22),
        _Panel(
          color: Colors.white,
          child: Wrap(
            spacing: 24,
            runSpacing: 14,
            children: [
              _Stat(
                label: '연습한 문제',
                value: '$completed / ${quizCatalog.length}',
              ),
              _Stat(label: '다시 볼 문제', value: '${_knownWrong.length}'),
              _Stat(label: '저장한 문제', value: '${_knownBookmarks.length}'),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Text('어떤 연습을 해볼까요?', style: _sectionHeading(context)),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(1);
            final columns = constraints.maxWidth >= 800 && scale < 1.6
                ? 4
                : constraints.maxWidth >= 270 && scale < 1.6
                ? 2
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 14) / columns;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final category in TrainingCategory.values)
                  SizedBox(
                    width: width,
                    child: _categoryCard(context, category),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        const _Hint(
          icon: Icons.lightbulb_outline_rounded,
          text: '정답을 확인한 뒤 예시 음성을 들을 수 있어요. 헷갈린 문제는 복습에 모아둘게요.',
        ),
        const SizedBox(height: 16),
        Text(
          catalogReadingNote,
          style: const TextStyle(color: muted, fontSize: 14, height: 1.6),
        ),
      ],
    );
  }

  Widget _categoryCard(BuildContext context, TrainingCategory category) {
    final items = quizCatalog
        .where((item) => item.category == category)
        .toList();
    final completed = items
        .where((item) => widget.learning.answers.containsKey(item.id))
        .length;
    final colors = [
      const Color(0xfffff4ab),
      const Color(0xffeed8fc),
      const Color(0xffd3ebff),
      const Color(0xffcff0df),
    ];
    final icons = [
      Icons.abc_rounded,
      Icons.waving_hand_outlined,
      Icons.forum_outlined,
      Icons.business_center_outlined,
    ];
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: line),
      ),
      child: InkWell(
        key: ValueKey('category-${category.name}'),
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() {
          _category = category;
          _group = null;
        }),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors[category.index],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icons[category.index], color: ink, size: 26),
              ),
              const SizedBox(height: 16),
              Text(
                category.label,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                category.subtitle,
                style: const TextStyle(color: ink, height: 1.5, fontSize: 16),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '$completed / ${items.length}문제 연습',
                    style: const TextStyle(color: ink, fontSize: 14),
                  ),
                  const Icon(Icons.arrow_forward_rounded, size: 18, color: ink),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<QuizItem> get _knownWrong => quizCatalog
      .where((item) => widget.learning.wrongIds.contains(item.id))
      .toList();

  List<QuizItem> get _knownBookmarks => quizCatalog
      .where((item) => widget.learning.bookmarkedIds.contains(item.id))
      .toList();

  Widget _buildCategory(BuildContext context) {
    final category = _category!;
    final all = quizCatalog.where((item) => item.category == category).toList();
    final groups = all.map((item) => item.group).toSet().toList();
    final visible = _group == null
        ? all
        : all.where((item) => item.group == _group).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _backButton('전체 분류', () => setState(() => _category = null)),
        const SizedBox(height: 14),
        const _Eyebrow('발음 구별 퀴즈'),
        const SizedBox(height: 10),
        Text(category.label, style: _heading(context)),
        const SizedBox(height: 8),
        Text(
          category.subtitle,
          style: const TextStyle(color: muted, height: 1.6),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('전체'),
              selected: _group == null,
              onSelected: (_) => setState(() => _group = null),
            ),
            for (final group in groups)
              ChoiceChip(
                label: Text(group),
                selected: _group == group,
                onSelected: (_) => setState(() => _group = group),
              ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const ValueKey('quiz-start-group'),
          onPressed: visible.isEmpty ? null : () => _startSession(visible),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text('${_group ?? category.label} 연습하기 · ${visible.length}문제'),
        ),
        const SizedBox(height: 26),
        Text('시작할 문제를 골라도 좋아요', style: _sectionHeading(context)),
        const SizedBox(height: 12),
        ..._questionList(visible),
      ],
    );
  }

  Widget _buildReview(BuildContext context) {
    final wrong = _knownWrong;
    final bookmarks = _knownBookmarks;
    final both = {
      ...wrong.map((item) => item.id),
      ...bookmarks.map((item) => item.id),
    };
    final visible = switch (_reviewFilter) {
      _ReviewFilter.wrong => wrong,
      _ReviewFilter.bookmarks => bookmarks,
      _ReviewFilter.all =>
        quizCatalog.where((item) => both.contains(item.id)).toList(),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Eyebrow('익숙해질 때까지, 천천히'),
        const SizedBox(height: 10),
        Text('다시 보는 발음', style: _heading(context)),
        const SizedBox(height: 10),
        const Text(
          '헷갈렸던 문제와 저장한 문제를 모았어요.\n다시 맞힌 문제는 오답 목록에서 빠져요.',
          style: TextStyle(color: muted, height: 1.6),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              key: const ValueKey('review-wrong'),
              label: Text('오답 ${wrong.length}'),
              selected: _reviewFilter == _ReviewFilter.wrong,
              onSelected: (_) =>
                  setState(() => _reviewFilter = _ReviewFilter.wrong),
            ),
            ChoiceChip(
              key: const ValueKey('review-bookmarks'),
              label: Text('저장 ${bookmarks.length}'),
              selected: _reviewFilter == _ReviewFilter.bookmarks,
              onSelected: (_) =>
                  setState(() => _reviewFilter = _ReviewFilter.bookmarks),
            ),
            ChoiceChip(
              label: Text('전체 ${both.length}'),
              selected: _reviewFilter == _ReviewFilter.all,
              onSelected: (_) =>
                  setState(() => _reviewFilter = _ReviewFilter.all),
            ),
          ],
        ),
        const SizedBox(height: 22),
        if (visible.isEmpty)
          _Panel(
            color: Colors.white,
            child: Column(
              children: [
                const Icon(Icons.auto_stories_outlined, color: muted, size: 42),
                const SizedBox(height: 16),
                Text(
                  _reviewFilter == _ReviewFilter.bookmarks
                      ? '저장한 문제가 아직 없어요'
                      : _reviewFilter == _ReviewFilter.wrong
                      ? '다시 볼 오답이 아직 없어요'
                      : '복습할 문제가 아직 없어요',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '발음 훈련에서 문제를 풀거나\n북마크를 눌러 여기에 모아보세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, height: 1.6),
                ),
              ],
            ),
          )
        else ...[
          FilledButton.icon(
            key: const ValueKey('quiz-start-review'),
            onPressed: () => _startSession(visible),
            icon: const Icon(Icons.replay_rounded),
            label: Text('${visible.length}문제 복습하기'),
          ),
          const SizedBox(height: 20),
          ..._questionList(visible, showCategory: true),
        ],
      ],
    );
  }

  List<Widget> _questionList(
    List<QuizItem> items, {
    bool showCategory = false,
  }) => [
    for (var index = 0; index < items.length; index++) ...[
      _questionTile(
        items[index],
        () => _startSession(items, startAt: index),
        showCategory,
      ),
      const SizedBox(height: 10),
    ],
  ];

  Widget _questionTile(QuizItem item, VoidCallback onTap, bool showCategory) {
    final answered = widget.learning.answers[item.id];
    final bookmarked = widget.learning.bookmarkedIds.contains(item.id);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: line),
      ),
      child: InkWell(
        key: ValueKey('quiz-item-${item.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 6, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      showCategory
                          ? '${item.category.label} · ${item.group}'
                          : item.group,
                      style: const TextStyle(color: muted, fontSize: 14),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      item.text,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      answered == null
                          ? '아직 연습 전'
                          : answered
                          ? '지난 연습에서 맞혔어요'
                          : '한 번 더 연습해 보세요',
                      style: TextStyle(
                        color: answered == true
                            ? const Color(0xff267153)
                            : muted,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: bookmarked ? '저장 해제' : '문제 저장',
                onPressed: () =>
                    unawaited(widget.learning.toggleBookmark(item.id)),
                icon: Icon(
                  bookmarked
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                ),
                color: bookmarked ? blue : muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuestion(BuildContext context) {
    final item = _session![_index];
    final options = _options[item.id]!;
    final correct = _submitted && options[_selected!] == item.pronunciation;
    final bookmarked = widget.learning.bookmarkedIds.contains(item.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _backButton('목록으로', () => setState(_resetSession))),
            IconButton(
              key: const ValueKey('quiz-bookmark'),
              tooltip: bookmarked ? '저장 해제' : '문제 저장',
              onPressed: () =>
                  unawaited(widget.learning.toggleBookmark(item.id)),
              icon: Icon(
                bookmarked
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
              ),
              color: blue,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _Eyebrow('${item.category.label} · ${item.group}'),
        const SizedBox(height: 16),
        Text(
          '문제 ${_index + 1} / ${_session!.length}',
          style: const TextStyle(color: muted, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (_index + (_submitted ? 1 : 0)) / _session!.length,
            minHeight: 6,
            backgroundColor: line,
            color: blue,
            semanticsLabel: '문제 진행 상황',
          ),
        ),
        const SizedBox(height: 28),
        Text('어떻게 읽을까요?', style: _heading(context)),
        const SizedBox(height: 10),
        const Text('올바른 발음을 골라 주세요.', style: TextStyle(color: muted)),
        const SizedBox(height: 22),
        _Panel(
          color: const Color(0xffeef4ff),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '연습할 표현',
                style: TextStyle(color: muted, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Text(
                item.text,
                style: const TextStyle(
                  fontSize: 27,
                  height: 1.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final sideBySide =
                constraints.maxWidth >= 600 &&
                MediaQuery.textScalerOf(context).scale(1) < 1.5;
            final children = [
              for (var i = 0; i < options.length; i++)
                _optionCard(context, item, options[i], i),
            ];
            return sideBySide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: children[0]),
                      const SizedBox(width: 14),
                      Expanded(child: children[1]),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      children[0],
                      const SizedBox(height: 12),
                      children[1],
                    ],
                  );
          },
        ),
        const SizedBox(height: 20),
        if (!_submitted) ...[
          FilledButton(
            key: const ValueKey('quiz-submit'),
            onPressed: _selected == null ? null : _submit,
            child: const Text('정답 확인'),
          ),
          const SizedBox(height: 12),
          const Text(
            '괄호 안은 읽는 소리예요. 답을 고르면 발음 설명을 볼 수 있어요.',
            style: TextStyle(color: muted, fontSize: 14, height: 1.6),
          ),
        ] else ...[
          Semantics(
            liveRegion: true,
            child: _Panel(
              color: correct
                  ? const Color(0xffe7f5ee)
                  : const Color(0xfffff3e5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Icon(
                        correct
                            ? Icons.check_circle_outline_rounded
                            : Icons.lightbulb_outline_rounded,
                        color: correct
                            ? const Color(0xff267153)
                            : const Color(0xff925500),
                      ),
                      Text(
                        correct ? '맞았어요!' : '이렇게 읽어요',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _reading(item.pronunciation),
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.explanation,
                    style: const TextStyle(height: 1.7, fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  if (!correct)
                    const Text(
                      '이 문제는 복습 목록에 담았어요.',
                      style: TextStyle(color: muted, fontSize: 14, height: 1.5),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('quiz-speak'),
                        style: _compactButtonStyle(),
                        onPressed: _speaking ? null : () => _speak(item, false),
                        icon: const Icon(Icons.volume_up_outlined, size: 20),
                        label: const Text('예시 듣기'),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('quiz-speak-slow'),
                        style: _compactButtonStyle(),
                        onPressed: _speaking ? null : () => _speak(item, true),
                        icon: const Icon(
                          Icons.slow_motion_video_rounded,
                          size: 20,
                        ),
                        label: const Text('천천히 듣기'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Tooltip(
                    message: item.sourceUrl,
                    child: const Text(
                      '국립국어원 발음 자료를 참고했어요.',
                      style: TextStyle(color: muted, fontSize: 14, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const ValueKey('quiz-next'),
            onPressed: _next,
            icon: Icon(
              _index + 1 == _session!.length
                  ? Icons.flag_outlined
                  : Icons.arrow_forward_rounded,
            ),
            label: Text(_index + 1 == _session!.length ? '연습 결과 보기' : '다음 문제'),
          ),
        ],
      ],
    );
  }

  Widget _optionCard(
    BuildContext context,
    QuizItem item,
    String option,
    int index,
  ) {
    final selected = _selected == index;
    final isCorrect = _submitted && option == item.pronunciation;
    final isWrong = _submitted && selected && !isCorrect;
    final border = isCorrect
        ? const Color(0xff267153)
        : isWrong
        ? red
        : selected
        ? blue
        : line;
    final fill = isCorrect
        ? const Color(0xffe7f5ee)
        : isWrong
        ? const Color(0xffffedf0)
        : selected
        ? const Color(0xffedf3ff)
        : Colors.white;
    return Semantics(
      button: true,
      selected: selected,
      enabled: !_submitted,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: border, width: selected || isCorrect ? 2 : 1),
        ),
        child: InkWell(
          key: ValueKey('quiz-option-$index'),
          borderRadius: BorderRadius.circular(18),
          onTap: _submitted ? null : () => setState(() => _selected = index),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 132),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Icon(
                        isCorrect
                            ? Icons.check_circle_rounded
                            : isWrong
                            ? Icons.cancel_outlined
                            : selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        size: 23,
                        color: border,
                      ),
                      Text(
                        isCorrect
                            ? '${index == 0 ? 'A' : 'B'} · 정답'
                            : isWrong
                            ? '${index == 0 ? 'A' : 'B'} · 선택한 답'
                            : index == 0
                            ? 'A'
                            : 'B',
                        style: TextStyle(
                          color: _submitted ? border : muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _reading(option),
                    style: const TextStyle(
                      fontSize: 23,
                      height: 1.5,
                      fontWeight: FontWeight.w700,
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

  Widget _buildSummary(BuildContext context) {
    final total = _session!.length;
    return Column(
      key: const ValueKey('quiz-summary'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        const Icon(Icons.celebration_outlined, size: 58, color: blue),
        const SizedBox(height: 22),
        Text(
          '이번 연습을 마쳤어요',
          textAlign: TextAlign.center,
          style: _heading(context),
        ),
        const SizedBox(height: 12),
        const Text(
          '한 번 더 살펴보며 익숙해져도 좋아요.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, height: 1.6),
        ),
        const SizedBox(height: 26),
        _Panel(
          color: const Color(0xffedf3ff),
          child: Column(
            children: [
              const Text('이번 연습 결과', style: TextStyle(color: muted)),
              const SizedBox(height: 12),
              Text(
                '$total문제 중 $_correctCount문제 정답',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 27,
                  height: 1.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _sessionWrong.isEmpty
                    ? '모든 문제를 맞혔어요!'
                    : '헷갈린 ${_sessionWrong.length}문제는 복습 목록에 담았어요.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted, height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        if (_sessionWrong.isNotEmpty) ...[
          FilledButton.icon(
            key: const ValueKey('quiz-retry-wrong'),
            onPressed: () => _startSession(List.of(_sessionWrong)),
            icon: const Icon(Icons.replay_rounded),
            label: const Text('헷갈린 문제 다시 풀기'),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton(
          key: const ValueKey('quiz-retry-session'),
          onPressed: () => _startSession(List.of(_session!)),
          child: const Text('같은 문제 다시 풀기'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(_resetSession),
          child: const Text('목록으로 돌아가기'),
        ),
      ],
    );
  }

  Widget _backButton(String label, VoidCallback onTap) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: () {
        _stopVoice();
        onTap();
      },
      style: TextButton.styleFrom(
        foregroundColor: muted,
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
        minimumSize: const Size(0, 48),
        alignment: Alignment.centerLeft,
      ),
      icon: const Icon(Icons.arrow_back_rounded, size: 20),
      label: Text(label),
    ),
  );

  static String _reading(String value) =>
      value.startsWith('[') ? value : '[$value]';

  static TextStyle _heading(BuildContext context) => Theme.of(context)
      .textTheme
      .headlineMedium!
      .copyWith(color: ink, fontWeight: FontWeight.w800, height: 1.35);

  static TextStyle _sectionHeading(BuildContext context) => Theme.of(
    context,
  ).textTheme.titleMedium!.copyWith(color: ink, fontWeight: FontWeight.w700);

  static ButtonStyle _compactButtonStyle() => OutlinedButton.styleFrom(
    minimumSize: const Size(0, 48),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    backgroundColor: Colors.white,
  );
}

class _Eyebrow extends StatelessWidget {
  final String text;
  const _Eyebrow(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: blue,
      fontSize: 14,
      fontWeight: FontWeight.w700,
      height: 1.5,
    ),
  );
}

class _Panel extends StatelessWidget {
  final Widget child;
  final Color color;
  const _Panel({required this.child, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: line.withValues(alpha: 0.6)),
    ),
    child: child,
  );
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: const TextStyle(color: muted, fontSize: 14)),
      const SizedBox(height: 5),
      Text(
        value,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Hint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: muted, size: 21),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(color: muted, height: 1.65, fontSize: 14),
        ),
      ),
    ],
  );
}
