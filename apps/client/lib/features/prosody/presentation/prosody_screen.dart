import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../practice_feedback.dart';
import '../practice_session.dart';
import '../widgets/prosody_chart.dart';
import 'prosody_web_surface.dart';

enum ProsodyStep { prepare, record, result }

/// One task at a time: choose a phrase, record, then review the accepted result.
class ProsodyScreen extends StatefulWidget {
  const ProsodyScreen({
    super.key,
    this.session,
    this.onExit,
    this.suspended = false,
  });
  final PracticeSession? session;
  final Future<void> Function()? onExit;
  final bool suspended;
  @override
  State<ProsodyScreen> createState() => _ProsodyScreenState();
}

class _ProsodyScreenState extends State<ProsodyScreen>
    with WidgetsBindingObserver {
  late final PracticeSession s;
  late ProsodyStep _step;
  PracticeResult? _lastResult;
  final _script = TextEditingController();
  bool _backInFlight = false, _recordAttempted = false;
  bool get _stopping => _backInFlight || s.phase == PracticePhase.cancelling;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    s = widget.session ?? PracticeSession();
    _lastResult = s.result;
    _step = s.recording
        ? ProsodyStep.record
        : s.result != null
        ? ProsodyStep.result
        : ProsodyStep.prepare;
    s.addListener(_changed);
    if (widget.session == null && !kIsWeb) unawaited(s.initialize());
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      final next = s.result;
      // A failed retry keeps the old object. Never navigate on that failure.
      if (next != null && !identical(next, _lastResult)) {
        _step = ProsodyStep.result;
        _recordAttempted = false;
      } else if (next == null && _step == ProsodyStep.result) {
        _step = s.reference == null ? ProsodyStep.prepare : ProsodyStep.record;
      }
      _lastResult = next;
    });
  }

  @override
  void didUpdateWidget(covariant ProsodyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!kIsWeb && widget.suspended && !oldWidget.suspended) {
      unawaited(s.audio.stopPlayback());
      if (s.busy) unawaited(s.cancelCurrent());
    }
  }

  void _show(ProsodyStep step) {
    if (s.busy || _backInFlight) return;
    if (step == ProsodyStep.record && s.reference == null) return;
    if (step == ProsodyStep.result && s.result == null) return;
    FocusScope.of(context).unfocus();
    unawaited(s.audio.stopPlayback());
    setState(() {
      _step = step;
      _recordAttempted = false;
    });
  }

  Future<void> _back() async {
    if (_stopping) return;
    setState(() => _backInFlight = true);
    final wasBusy = s.busy;
    try {
      if (wasBusy) {
        await s.cancelCurrent(
          message: '잠시 멈췄어요. 준비되면 다시 시작해 주세요. 이전 결과는 보관했어요.',
        );
      }
      await s.audio.stopPlayback();
      if (!mounted) return;
      if (!wasBusy && _step == ProsodyStep.prepare && widget.onExit != null) {
        await widget.onExit!();
        return;
      }
      setState(() {
        if (!wasBusy) {
          if (_step == ProsodyStep.result) {
            _step = ProsodyStep.record;
          } else if (_step == ProsodyStep.record) {
            _step = ProsodyStep.prepare;
          }
          _recordAttempted = false;
        }
      });
    } finally {
      _backInFlight = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(s.audio.stopPlayback());
      if (s.busy) {
        unawaited(s.cancelCurrent(message: '화면을 벗어나 녹음을 멈췄어요. 이전 결과는 보관했어요.'));
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    s.removeListener(_changed);
    if (widget.session == null) s.dispose();
    _script.dispose();
    super.dispose();
  }

  Widget _heading(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.4,
    ),
  );

  Widget _copy(String text, {double size = 16, Color? color}) => Text(
    text,
    style: TextStyle(fontSize: size, height: 1.6, color: color),
  );

  Widget _status() => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: _copy(s.status, size: 14),
    ),
  );

  Widget _bottom(List<Widget> children) => Material(
    color: const Color(0xeef8fbff),
    child: SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xffdce5f2))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );

  Widget _featurePicker() => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      ChoiceChip(
        label: const Text('높낮이'),
        selected: !s.volume,
        onSelected: (_) => s.setVolume(false),
      ),
      ChoiceChip(
        label: const Text('강약'),
        selected: s.volume,
        onSelected: (_) => s.setVolume(true),
      ),
    ],
  );

  Widget _prepareBody() => ListView(
    key: const PageStorageKey('prosody-prepare-scroll'),
    padding: const EdgeInsets.all(16),
    children: [
      _heading('먼저 읽을 문구를 골라 주세요'),
      const SizedBox(height: 8),
      _copy('편한 목소리로 시작해 보세요. 한 번에 똑같이 따라 하지 않아도 괜찮아요.'),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            key: const Key('prosody-preset-mode'),
            label: const Text('예시 문구'),
            selected: !s.usingScript,
            onSelected: s.busy ? null : (_) => s.setMode(false),
          ),
          ChoiceChip(
            key: const Key('prosody-script-mode'),
            label: const Text('내 대본'),
            selected: s.usingScript,
            onSelected: s.busy ? null : (_) => s.setMode(true),
          ),
        ],
      ),
      if (s.usingScript) ...[
        const SizedBox(height: 16),
        TextField(
          key: const Key('prosody-script-input'),
          controller: _script,
          enabled: !s.busy,
          maxLength: 2000,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: '연습할 대본',
            hintText: '안녕하세요. 오늘은 저희 프로젝트를 소개하겠습니다.',
            border: OutlineInputBorder(),
          ),
          style: const TextStyle(fontSize: 17, height: 1.6),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          key: const Key('prosody-apply-script'),
          onPressed: s.busy
              ? null
              : () {
                  FocusScope.of(context).unfocus();
                  s.applyScript(_script.text);
                },
          child: const Text('대본으로 문구 준비', textAlign: TextAlign.center),
        ),
      ],
      const SizedBox(height: 20),
      if (s.phrases.isNotEmpty)
        DropdownButtonFormField<int>(
          key: ValueKey(
            'prosody-phrase-${s.usingScript}-${s.index}-${s.phrases.join()}',
          ),
          initialValue: s.index,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '연습할 문구'),
          items: [
            for (var i = 0; i < s.phrases.length; i++)
              DropdownMenuItem(
                value: i,
                child: Text(
                  '${i + 1}. ${s.phrases[i]}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: s.busy
              ? null
              : (value) {
                  if (value != null) s.choose(value);
                },
        ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xffdce5f2)),
        ),
        child: _copy(s.phrase, size: 23),
      ),
      const SizedBox(height: 10),
      _copy(
        s.reference?.source ?? '이 문구의 한국어 가이드를 먼저 만들어 주세요.',
        size: 14,
        color: const Color(0xff52647b),
      ),
      if (!s.usingScript && s.reference == null && !s.busy)
        OutlinedButton(
          onPressed: s.initialize,
          child: const Text('예시 다시 불러오기', textAlign: TextAlign.center),
        ),
      if (s.usingScript) ...[
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          key: const Key('prosody-generate-guide'),
          onPressed: s.busy || s.phrases.isEmpty ? null : s.generateGuide,
          icon: const Icon(Icons.graphic_eq),
          label: Text(
            s.reference == null ? '한국어 가이드 만들기' : '한국어 가이드 다시 만들기',
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        _copy('기기에 설치된 오프라인 한국어 음성으로 이 문구의 가이드와 그래프를 만들어요.', size: 14),
      ],
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: s.busy || s.reference == null ? null : s.playGuide,
        icon: const Icon(Icons.play_arrow),
        label: const Text('가이드 듣기 · 선택', textAlign: TextAlign.center),
      ),
      if (s.phase == PracticePhase.loading ||
          s.phase == PracticePhase.generating)
        const LinearProgressIndicator(),
      _status(),
      _copy(
        '가이드는 한 가지 읽기 예시예요. 말하기 실력이나 자연스러움을 채점하지 않아요.',
        size: 14,
        color: const Color(0xff52647b),
      ),
    ],
  );

  Widget _prepareControls() => _bottom([
    FilledButton(
      key: const Key('prosody-prepare-next'),
      onPressed: s.busy || _backInFlight || s.reference == null
          ? null
          : () => _show(ProsodyStep.record),
      child: const Text('이 문구로 연습하기', textAlign: TextAlign.center),
    ),
    if (s.busy)
      TextButton(
        onPressed: _backInFlight ? null : _back,
        child: const Text('준비 취소'),
      ),
    if (!s.busy && s.result != null)
      TextButton(
        onPressed: _backInFlight ? null : () => _show(ProsodyStep.result),
        child: const Text('이전 결과 보기'),
      ),
  ]);

  void _showWholePhrase() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(child: _copy(s.phrase, size: 21)),
      ),
    );
  }

  Widget _recordBody() => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context);
      final phraseSpace = scale.scale(18) * 1.4 * 2 + 16;
      final pickerSpace = scale.scale(14) * 1.5 + 26;
      final helpSpace = scale.scale(13) * 1.6 * 2 + 16;
      final legendSpace = scale.scale(12) * 1.5 + 12;
      final graphHeight =
          (constraints.maxHeight -
                  phraseSpace -
                  pickerSpace -
                  helpSpace -
                  legendSpace -
                  24)
              .clamp(180.0, 400.0);
      final hint = _stopping
          ? '잠시 멈추고 있어요. 이전 결과는 보관해 둘게요.'
          : !s.recording
          ? '파란 선은 이 문구의 읽기 예시예요. 녹음하면 내 목소리를 짙은 회색 선으로 보여드려요.'
          : s.currentVoice
          ? '지금 목소리를 짙은 회색 선과 점으로 보여드려요.'
          : '잠시 쉬어도 괜찮아요. 목소리가 잡히면 짙은 회색 점이 나타나요.';
      return SingleChildScrollView(
        key: const PageStorageKey('prosody-record-scroll'),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.phrase,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            if (s.phrase.runes.length > 35)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _showWholePhrase,
                  child: const Text('문구 전체 보기'),
                ),
              ),
            const SizedBox(height: 6),
            _featurePicker(),
            const SizedBox(height: 8),
            ProsodyChart(
              reference: s.reference?.analysis,
              // An accepted older result is never drawn as a new live take.
              trace: s.recording ? s.liveTrace : const [],
              volume: s.volume,
              live: s.recording,
              progress: s.recording
                  ? (s.liveTrace.isEmpty ? 0 : s.liveTrace.last.time)
                  : null,
              domainSeconds: s.recording ? s.liveDomain : null,
              scaleBound: s.recording
                  ? (s.volume ? s.levelBound : s.pitchBound)
                  : null,
              height: graphHeight,
            ),
            Semantics(
              liveRegion: true,
              child: _copy(hint, size: 14, color: const Color(0xff536987)),
            ),
            if (s.phase == PracticePhase.processing) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            if (_recordAttempted && !s.recording) _status(),
            if (!s.busy && s.result != null)
              TextButton(
                key: const Key('prosody-previous-result'),
                onPressed: () => _show(ProsodyStep.result),
                child: const Text('이전 결과 보기'),
              ),
          ],
        ),
      );
    },
  );

  Widget _recordControls() => _bottom([
    Text(
      _stopping
          ? '잠시 멈추고 있어요'
          : s.recording
          ? '녹음 중 · 00:${s.seconds.floor().toString().padLeft(2, '0')}'
          : s.phase == PracticePhase.processing
          ? '녹음을 확인하고 있어요'
          : '최대 20초',
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 14, height: 1.4),
    ),
    const SizedBox(height: 6),
    FilledButton.icon(
      key: const Key('prosody-record-toggle'),
      onPressed:
          _backInFlight || (s.busy && !s.recording) || s.reference == null
          ? null
          : _toggleRecording,
      icon: Icon(s.recording ? Icons.stop_rounded : Icons.mic_rounded),
      label: Text(
        _stopping
            ? '멈추는 중'
            : s.recording
            ? '녹음 마치기'
            : s.phase == PracticePhase.processing
            ? '확인 중'
            : '녹음 시작',
        textAlign: TextAlign.center,
      ),
    ),
    if (s.busy)
      TextButton(
        key: const Key('prosody-record-cancel'),
        onPressed: _stopping ? null : _back,
        child: const Text('녹음 취소', textAlign: TextAlign.center),
      ),
  ]);

  Future<void> _toggleRecording() async {
    if (_backInFlight) return;
    if (s.recording) {
      await s.stopRecording();
      return;
    }
    if (s.busy || s.reference == null) return;
    setState(() => _recordAttempted = true);
    await s.startRecording();
  }

  void _practiceSelected() {
    if (s.busy || _backInFlight) return;
    if (s.excerpt) {
      _show(ProsodyStep.record);
      return;
    }
    final before = s.reference;
    s.practiceSelected();
    if (s.excerpt && !identical(before, s.reference)) _show(ProsodyStep.record);
  }

  void _wholeRecord() {
    if (s.busy || _backInFlight) return;
    if (s.excerpt) s.leaveExcerpt();
    _show(ProsodyStep.record);
  }

  Widget _resultBody() {
    final result = s.result!, reference = s.reference!;
    final feedback = s.feedback;
    return ListView(
      key: const PageStorageKey('prosody-result-scroll'),
      padding: const EdgeInsets.all(16),
      children: [
        _heading('내 목소리를 함께 살펴봐요'),
        const SizedBox(height: 8),
        _copy(s.phrase, size: 17),
        if (result.demo)
          _copy(
            '합성 시험 신호예요. 실제 사람의 녹음은 아니에요.',
            size: 14,
            color: const Color(0xff94662d),
          ),
        const SizedBox(height: 8),
        _featurePicker(),
        const SizedBox(height: 8),
        ProsodyChart(
          reference: reference.analysis,
          trace: result.trace,
          volume: s.volume,
          selected: s.segment,
          regions: result.summary.segments,
        ),
        const SizedBox(height: 8),
        _copy(
          [
            '파란 점선은 예시, 짙은 회색 선은 내 목소리예요. 녹음 뒤에는 읽는 속도를 대략 맞춰 겹쳐 보여줘요.',
            if (result.summary.segmentationNote.isNotEmpty)
              result.summary.segmentationNote,
          ].join('\n\n'),
          size: 14,
          color: const Color(0xff52647b),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < result.summary.segments.length; i++)
              ChoiceChip(
                key: ValueKey('prosody-region-$i'),
                label: Text(result.summary.segments[i].label),
                selected: s.selected == i,
                onSelected: s.busy ? null : (_) => s.selectRegion(i),
              ),
          ],
        ),
        if (feedback != null) ...[
          const SizedBox(height: 18),
          _feedbackCard(feedback),
          const SizedBox(height: 12),
          ExpansionTile(
            key: const PageStorageKey('prosody-measurement-details'),
            title: const Text('측정값과 비교 방법'),
            tilePadding: EdgeInsets.zero,
            children: [
              _copy(feedback.detail, size: 14),
              for (final part in result.summary.segments)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _copy(
                    '${part.label} 평균 차이 · 높낮이 ${part.pitchError?.toStringAsFixed(1) ?? '미측정'}반음 / 강약 ${part.levelError?.toStringAsFixed(1) ?? '미측정'}dB',
                    size: 14,
                  ),
                ),
              _copy(
                '시간 구간을 비교한 것이며 단어나 음절을 자동으로 찾은 결과는 아니에요. 소리 크기는 각 녹음 안의 상대값이에요.',
                size: 14,
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: s.busy ? null : () => s.playGuide(region: true),
          child: const Text('이 부분 가이드 듣기 · 선택', textAlign: TextAlign.center),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: s.busy ? null : () => s.playUser(region: true),
          child: const Text('이 부분 내 목소리 듣기 · 선택', textAlign: TextAlign.center),
        ),
        _status(),
        _copy(
          '음성과 대본은 이 기기 안에서 처리해요. 재생에 필요한 앱 임시 파일을 사용해요.',
          size: 14,
          color: const Color(0xff52647b),
        ),
      ],
    );
  }

  Widget _feedbackCard(PracticeFeedback feedback) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xffdce5f2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(feedback.title),
        const SizedBox(height: 14),
        Text(
          '이번 목소리',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        _copy(feedback.observation, size: 16),
        const SizedBox(height: 14),
        Text(
          '다음엔 이렇게 해 봐요',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        _copy(feedback.action, size: 16),
      ],
    ),
  );

  Widget _resultControls() => _bottom([
    FilledButton(
      key: const Key('prosody-practice-region'),
      onPressed: s.busy || _backInFlight || s.segment == null
          ? null
          : _practiceSelected,
      child: Text(
        s.excerpt ? '이 부분 다시 읽기' : '선택한 부분 연습하기',
        textAlign: TextAlign.center,
      ),
    ),
    TextButton(
      key: const Key('prosody-repeat-whole'),
      onPressed: s.busy || _backInFlight ? null : _wholeRecord,
      child: const Text('전체 문구 다시 읽기', textAlign: TextAlign.center),
    ),
  ]);

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return ProsodyWebSurface(
        onExit: widget.onExit,
        suspended: widget.suspended,
      );
    }
    final title = switch (_step) {
      ProsodyStep.prepare => '연습 준비',
      ProsodyStep.record => '목소리 녹음',
      ProsodyStep.result => '내 목소리 결과',
    };
    return Theme(
      data: Theme.of(context).copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: Theme.of(context).filledButtonTheme.style?.copyWith(
            minimumSize: const WidgetStatePropertyAll(Size(48, 50)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: Theme.of(context).outlinedButtonTheme.style?.copyWith(
            minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          ),
        ),
      ),
      child: PopScope(
        canPop:
            _step == ProsodyStep.prepare &&
            !s.busy &&
            !_backInFlight &&
            widget.onExit == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_back());
        },
        child: Scaffold(
          backgroundColor: const Color(0xfff1f5fc),
          appBar: AppBar(
            backgroundColor: const Color(0xeef8fbff),
            automaticallyImplyLeading: false,
            leading:
                _step != ProsodyStep.prepare || s.busy || widget.onExit != null
                ? IconButton(
                    key: const Key('prosody-back'),
                    onPressed: _stopping ? null : _back,
                    tooltip: s.busy
                        ? '현재 작업 멈추기'
                        : _step == ProsodyStep.prepare
                        ? '음량 측정으로 돌아가기'
                        : '이전 단계',
                    icon: const Icon(Icons.arrow_back),
                  )
                : null,
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    '${_step.index + 1} / 3',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
          body: AbsorbPointer(
            absorbing: _backInFlight,
            child: SafeArea(
              bottom: false,
              child: switch (_step) {
                ProsodyStep.prepare => _prepareBody(),
                ProsodyStep.record => _recordBody(),
                ProsodyStep.result => _resultBody(),
              },
            ),
          ),
          bottomNavigationBar: switch (_step) {
            ProsodyStep.prepare => _prepareControls(),
            ProsodyStep.record => _recordControls(),
            ProsodyStep.result => _resultControls(),
          },
        ),
      ),
    );
  }
}
