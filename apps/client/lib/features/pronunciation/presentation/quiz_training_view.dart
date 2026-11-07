import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app_theme.dart';
import '../data/learning_store.dart';
import '../domain/quiz_catalog.dart';

enum ReviewFilter { all, wrong, bookmarks, guides }

class QuizTrainingView extends StatefulWidget {
  const QuizTrainingView({
    super.key,
    required this.learning,
    required this.onPractice,
    this.onOpenGuide,
    this.reviewOnly = false,
    this.reviewInitialFilter = ReviewFilter.all,
    this.reviewFilterRequest = 0,
    this.active = true,
  });
  final LearningController learning;
  final ValueChanged<QuizItem> onPractice;
  final ValueChanged<String>? onOpenGuide;
  final bool reviewOnly;
  final ReviewFilter reviewInitialFilter;
  final int reviewFilterRequest;
  final bool active;
  @override
  State<QuizTrainingView> createState() => _QuizTrainingViewState();
}

class _QuizTrainingViewState extends State<QuizTrainingView> {
  TrainingCategory? category;
  String? group;
  late ReviewFilter filter;
  @override
  void initState() {
    super.initState();
    filter = widget.reviewInitialFilter;
  }

  @override
  void didUpdateWidget(covariant QuizTrainingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reviewFilterRequest != widget.reviewFilterRequest ||
        oldWidget.reviewInitialFilter != widget.reviewInitialFilter)
      filter = widget.reviewInitialFilter;
  }

  void _back() => setState(() {
    if (group != null) {
      group = null;
    } else {
      category = null;
    }
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.learning,
    builder: (context, _) {
      if (!widget.learning.ready)
        return const Center(child: CircularProgressIndicator());
      return PopScope<void>(
        canPop: !widget.active || category == null || widget.reviewOnly,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && widget.active) _back();
        },
        child: ListView(
          key: ValueKey(
            'practice-list-${widget.reviewOnly}-$category-$group-$filter',
          ),
          padding: const EdgeInsets.symmetric(vertical: 24),
          children: widget.reviewOnly
              ? _review()
              : category == null
              ? _categories()
              : _expressions(),
        ),
      );
    },
  );

  List<Widget> _categories() => [
    const Text('읽고 비교하는 발음 연습', style: sectionTitle),
    const SizedBox(height: 8),
    const Text(
      '단어나 문장을 고르고 소리 내어 읽으면 된다. 녹음한 발음과 참고 발음을 비교할 수 있다.',
      style: smallCopy,
    ),
    const SizedBox(height: 24),
    for (final value in TrainingCategory.values) ...[
      _row(
        key: ValueKey('category-${value.name}'),
        title: value.label,
        subtitle:
            '${quizCatalog.where((item) => item.category == value).length}개 표현 · ${value.subtitle}',
        onTap: () => setState(() => category = value),
      ),
      const SizedBox(height: 12),
    ],
    const SizedBox(height: 12),
    const Text(
      '음성과 분석 결과는 기기 안에서 처리한다. 모델이 추정한 발음을 비교하는 기능이며 실제 판별 정확도는 검증 전이다.',
      style: smallCopy,
    ),
  ];

  List<Widget> _expressions() {
    final items = quizCatalog
        .where((item) => item.category == category)
        .toList();
    final groups = items.map((item) => item.group).toSet().toList();
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('practice-catalog-back'),
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
          label: Text(group == null ? '분류로' : '주제로'),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        group == null ? category!.label : groupTitle(group!),
        style: sectionTitle,
      ),
      const SizedBox(height: 18),
      if (group == null)
        for (var i = 0; i < groups.length; i++) ...[
          _row(
            key: ValueKey('quiz-group-${category!.name}-$i'),
            title: groupTitle(groups[i]),
            subtitle:
                '${items.where((item) => item.group == groups[i]).length}개 표현',
            onTap: () => setState(() => group = groups[i]),
          ),
          const SizedBox(height: 10),
        ]
      else
        for (final item in items.where((item) => item.group == group)) ...[
          _item(item),
          const SizedBox(height: 10),
        ],
      const SizedBox(height: 16),
      const Text(
        '참고 발음은 어절별로 끊어 읽는 기준이다. 말 사이의 이어 읽기와 소리의 길이는 판정 범위에 포함하지 않는다.',
        style: smallCopy,
      ),
    ];
  }

  List<Widget> _review() {
    final learning = widget.learning;
    final visible = quizCatalog
        .where(
          (item) => switch (filter) {
            ReviewFilter.wrong => learning.wrongIds.contains(item.id),
            ReviewFilter.bookmarks => learning.bookmarkedIds.contains(item.id),
            ReviewFilter.guides => false,
            ReviewFilter.all =>
              learning.wrongIds.contains(item.id) ||
                  learning.bookmarkedIds.contains(item.id),
          },
        )
        .toList();
    final guides = filter == ReviewFilter.all || filter == ReviewFilter.guides
        ? learning.guides
        : <SavedGuide>[];
    return [
      const Text('다시 읽을 표현', style: sectionTitle),
      const SizedBox(height: 10),
      const Text('저장한 표현과 이전 퀴즈 기록에서 다시 읽을 문장을 고르면 된다.', style: smallCopy),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final value in ReviewFilter.values)
            ChoiceChip(
              key: ValueKey('review-${value.name}'),
              selected: filter == value,
              onSelected: (_) => setState(() => filter = value),
              label: Text(switch (value) {
                ReviewFilter.all => '전체',
                ReviewFilter.wrong => '이전 퀴즈 오답',
                ReviewFilter.bookmarks => '저장한 표현',
                ReviewFilter.guides => '저장한 내 문장 ${learning.guides.length}',
              }),
            ),
        ],
      ),
      const SizedBox(height: 20),
      if (visible.isEmpty && guides.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Text(
            filter == ReviewFilter.guides
                ? '저장한 내 문장이 아직 없다.'
                : '복습할 표현이 아직 없다.',
            style: smallCopy,
          ),
        ),
      for (final item in visible) ...[_item(item), const SizedBox(height: 10)],
      for (final guide in guides) ...[
        _row(
          key: ValueKey('review-guide-${guide.text}'),
          title: guide.text,
          subtitle: '내 문장 · 눌러서 발음 연습',
          onTap: widget.onOpenGuide == null
              ? null
              : () => widget.onOpenGuide!(guide.text),
          trailing: IconButton(
            key: ValueKey('review-guide-delete-${guide.text}'),
            tooltip: '내 문장 삭제',
            onPressed: () => unawaited(learning.deleteGuide(guide.text)),
            icon: const Icon(Icons.delete_outline),
            color: muted,
          ),
        ),
        const SizedBox(height: 10),
      ],
      if (learning.answers.isNotEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 18),
          child: Text(
            '이전 퀴즈 기록은 그대로 보관한다. 녹음 결과로 과거 정답·오답 기록을 바꾸지 않는다.',
            style: smallCopy,
          ),
        ),
    ];
  }

  Widget _item(QuizItem item) {
    final learning = widget.learning,
        saved = learning.bookmarkedIds.contains(item.id);
    return _row(
      key: ValueKey('quiz-item-${item.id}'),
      title: item.text,
      subtitle: learning.answers.containsKey(item.id)
          ? '이전 퀴즈: ${learning.answers[item.id]! ? '정답' : '오답'} · 지금은 읽기 연습'
          : '눌러서 녹음하고 비교',
      onTap: () => widget.onPractice(item),
      trailing: IconButton(
        key: ValueKey('practice-bookmark-${item.id}'),
        tooltip: saved ? '저장 해제' : '표현 저장',
        onPressed: () => unawaited(learning.toggleBookmark(item.id)),
        icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
        color: accent,
      ),
    );
  }

  Widget _row({
    required Key key,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
  }) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: const BorderSide(color: line),
    ),
    child: InkWell(
      key: key,
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 10, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(subtitle, style: smallCopy),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ?? const Icon(Icons.chevron_right, color: muted),
          ],
        ),
      ),
    ),
  );
}
