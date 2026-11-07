import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app_theme.dart';
import '../data/pronunciation_recorder_contract.dart';
import '../domain/pronunciation_comparison.dart';
import 'speech_controls.dart';

enum _Phase {
  idle,
  preparing,
  ready,
  starting,
  recording,
  analyzing,
  playing,
  cancelling,
}

class PronunciationPracticeView extends StatefulWidget {
  const PronunciationPracticeView({
    super.key,
    required this.text,
    required this.references,
    required this.recorder,
    required this.playback,
    required this.onExit,
    this.referenceIsApproximate = false,
    this.referenceNote,
    this.onBookmark,
    this.bookmarked = false,
  });
  final String text;
  final List<String> references;
  final PronunciationRecorder recorder;
  final SpeechPlaybackController playback;
  final Future<void> Function() onExit;
  final bool referenceIsApproximate;
  final String? referenceNote;
  final VoidCallback? onBookmark;
  final bool bookmarked;
  @override
  State<PronunciationPracticeView> createState() =>
      _PronunciationPracticeViewState();
}

class _PronunciationPracticeViewState extends State<PronunciationPracticeView>
    with WidgetsBindingObserver {
  _Phase phase = _Phase.idle;
  String status = '모델을 준비한 뒤 마이크를 누르고 읽으면 된다.';
  PronunciationComparison? result;
  Timer? ticker;
  final stopwatch = Stopwatch();
  int epoch = 0;
  bool exiting = false;
  bool get usable => phase == _Phase.idle || phase == _Phase.ready;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached)
      unawaited(_cancel());
  }

  @override
  void dispose() {
    ++epoch;
    ticker?.cancel();
    stopwatch.stop();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.recorder.cancel());
    unawaited(widget.playback.stop(owner: this));
    super.dispose();
  }

  bool current(int ticket) => mounted && ticket == epoch && !exiting;
  void _set(_Phase value, String message) {
    if (!mounted) return;
    if (value != _Phase.recording) {
      ticker?.cancel();
      ticker = null;
      stopwatch.stop();
    }
    setState(() {
      phase = value;
      status = message;
    });
  }

  void _error(Object error, int ticket) {
    if (!current(ticket)) return;
    final cleanupTicket = ++epoch;
    final message = error.toString().replaceFirst(
      RegExp(r'^(Bad state: |Exception: |StateError: )'),
      '',
    );
    _set(_Phase.cancelling, message);
    unawaited(
      widget.recorder.cancel().whenComplete(() {
        if (current(cleanupTicket)) _set(_Phase.idle, message);
      }),
    );
  }

  Future<void> _prepare() async {
    if (phase != _Phase.idle) return;
    final ticket = ++epoch;
    _set(_Phase.preparing, '발음 모델을 준비 중이다. 처음에는 약 356MB를 내려받는다.');
    try {
      await widget.recorder.prepare(
        onProgress: (message) {
          if (current(ticket)) _set(_Phase.preparing, message);
        },
      );
      if (current(ticket)) _set(_Phase.ready, '준비됐다. 마이크를 누르고 문장을 읽으면 된다.');
    } catch (error) {
      _error(error, ticket);
    }
  }

  Future<void> _start() async {
    if (phase != _Phase.ready) return;
    final ticket = ++epoch;
    setState(() => result = null);
    _set(_Phase.starting, '마이크 권한과 입력을 확인 중이다.');
    try {
      await widget.playback.stop();
      if (!current(ticket)) return;
      await widget.recorder.start(
        onLimit: () {
          if (current(ticket)) unawaited(_finish());
        },
        onError: (message) => _error(StateError(message), ticket),
      );
      if (!current(ticket)) return;
      stopwatch
        ..reset()
        ..start();
      _set(_Phase.recording, '읽고 나서 마이크를 다시 누르면 분석한다.');
      ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (current(ticket)) setState(() {});
      });
    } catch (error) {
      _error(error, ticket);
    }
  }

  Future<void> _finish() async {
    if (phase != _Phase.recording) return;
    final ticket = epoch;
    _set(_Phase.analyzing, '기기 안에서 발음을 분석 중이다.');
    try {
      final phones = await widget.recorder.finish();
      if (!current(ticket)) return;
      result = comparePronunciation(
        phones: phones,
        references: widget.references,
        referenceIsApproximate: widget.referenceIsApproximate,
      );
      _set(_Phase.ready, '분석한 발음과 참고 발음을 비교했다. 다시 읽으며 확인하면 된다.');
    } catch (error) {
      _error(error, ticket);
    }
  }

  Future<void> _play() async {
    if (phase != _Phase.ready || result == null) return;
    final ticket = ++epoch;
    _set(_Phase.playing, '내 녹음을 재생 중이다.');
    try {
      await widget.playback.stop();
      if (!current(ticket)) return;
      await widget.recorder.play();
      if (current(ticket)) _set(_Phase.ready, '다시 읽으며 연습할 수 있다.');
    } catch (error) {
      _error(error, ticket);
    }
  }

  Future<void> _cancel() async {
    final ticket = ++epoch;
    _set(_Phase.cancelling, '녹음과 분석을 정리 중이다.');
    result = null;
    await widget.playback.stop(owner: this);
    await widget.recorder.cancel();
    if (current(ticket)) _set(_Phase.idle, '중지했다. 모델 준비 후 다시 읽을 수 있다.');
  }

  Future<void> _exit() async {
    if (exiting) return;
    exiting = true;
    ++epoch;
    _set(_Phase.cancelling, '녹음을 정리 중이다.');
    await widget.playback.stop(owner: this);
    await widget.recorder.cancel();
    if (mounted) await widget.onExit();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_exit());
    },
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('pronunciation-back'),
                        onPressed: exiting ? null : _exit,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('목록으로'),
                      ),
                    ),
                  ),
                  if (widget.onBookmark != null)
                    IconButton(
                      key: const Key('pronunciation-bookmark'),
                      tooltip: widget.bookmarked ? '저장 해제' : '표현 저장',
                      onPressed: widget.onBookmark,
                      icon: Icon(
                        widget.bookmarked
                            ? Icons.bookmark
                            : Icons.bookmark_border,
                      ),
                      color: accent,
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  Text(widget.text, style: pageTitle),
                  const SizedBox(height: 20),
                  _panel(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.referenceIsApproximate
                              ? '참고 발음 · 규칙 기반'
                              : '참고 발음',
                          style: smallCopy,
                        ),
                        const SizedBox(height: 10),
                        if (result == null)
                          Text(
                            widget.references.first,
                            style: const TextStyle(
                              fontSize: 24,
                              height: 1.5,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        else
                          _colored(
                            result!.expected,
                            const Key('pronunciation-expected'),
                          ),
                        if (widget.references.length > 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '허용 읽기: ${widget.references.join(' / ')}',
                              style: smallCopy,
                            ),
                          ),
                        const SizedBox(height: 12),
                        SpeechControls(
                          playback: widget.playback,
                          text: widget.text,
                          owner: this,
                          enabled: usable,
                          normalKey: const Key('pronunciation-speak'),
                          slowKey: const Key('pronunciation-speak-slow'),
                          normalLabel: '예시 발음 듣기',
                        ),
                        if (widget.referenceNote != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              widget.referenceNote!,
                              style: smallCopy,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('인식된 내 발음', style: sectionTitle),
                  const SizedBox(height: 10),
                  _panel(
                    result == null
                        ? const Text(
                            '녹음한 뒤 모델이 추정한 발음이 여기에 표시된다.',
                            style: smallCopy,
                          )
                        : _colored(
                            result!.observed,
                            const Key('pronunciation-observed'),
                          ),
                  ),
                  const SizedBox(height: 10),
                  const Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      Text('● 일치', style: TextStyle(color: accent)),
                      Text('− 차이', style: TextStyle(color: red)),
                      Text('… 불확실', style: TextStyle(color: muted)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '색은 추정 인식과 참고 읽기의 비교다. 실제 발음 판별 정확도는 검증 전이며 잡음이 글자로 인식될 수 있다.',
                    style: smallCopy,
                  ),
                  if (result != null) ...[
                    const SizedBox(height: 16),
                    for (final difference in result!.differences)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(difference),
                      ),
                    for (final note in result!.notes)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(note, style: smallCopy),
                      ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      key: const Key('pronunciation-replay'),
                      onPressed: phase == _Phase.ready ? _play : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('내 녹음 다시 듣기'),
                    ),
                  ],
                  if (phase == _Phase.idle) ...[
                    const SizedBox(height: 24),
                    const Text(
                      '최초 모델 준비에는 약 356MB 다운로드가 필요하다. 이후 녹음은 기기 안에서 처리한다.',
                      style: smallCopy,
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              decoration: const BoxDecoration(
                color: canvas,
                border: Border(top: BorderSide(color: line)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(status, style: smallCopy),
                  ),
                  if (phase == _Phase.recording)
                    Text(
                      '${(stopwatch.elapsedMilliseconds / 1000).clamp(0, 20).toStringAsFixed(1)} / 20초',
                      style: smallCopy,
                    ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    key: Key(
                      phase == _Phase.idle
                          ? 'pronunciation-prepare'
                          : 'pronunciation-mic',
                    ),
                    onPressed: phase == _Phase.idle
                        ? _prepare
                        : phase == _Phase.recording
                        ? _finish
                        : phase == _Phase.ready
                        ? _start
                        : null,
                    icon: Icon(
                      phase == _Phase.idle
                          ? Icons.download_outlined
                          : phase == _Phase.recording
                          ? Icons.stop
                          : Icons.mic,
                    ),
                    label: Text(
                      phase == _Phase.idle
                          ? '발음 모델 준비'
                          : phase == _Phase.recording
                          ? '녹음 종료 · 분석'
                          : result == null
                          ? '눌러서 읽기'
                          : '다시 읽기',
                    ),
                  ),
                  if (!usable && phase != _Phase.cancelling)
                    TextButton(
                      key: const Key('pronunciation-cancel'),
                      onPressed: _cancel,
                      child: const Text('중지'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: line),
    ),
    child: child,
  );

  Widget _colored(List<PronunciationSpan> spans, Key key) => Text.rich(
    key: key,
    TextSpan(
      children: [
        for (final span in spans)
          TextSpan(
            text: span.text,
            style: TextStyle(
              color: switch (span.mark) {
                ComparisonMark.match => accent,
                ComparisonMark.different => red,
                ComparisonMark.uncertain => muted,
              },
              decoration: span.mark == ComparisonMark.different
                  ? TextDecoration.underline
                  : null,
            ),
          ),
      ],
    ),
    style: const TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w700,
      height: 1.6,
    ),
  );
}
