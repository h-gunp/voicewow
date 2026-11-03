import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../practice_session.dart';
import '../widgets/prosody_chart.dart';
import '../practice_feedback.dart';

class ProsodyScreen extends StatefulWidget {
  const ProsodyScreen({super.key, this.session});
  final PracticeSession? session;
  @override
  State<ProsodyScreen> createState() => _ProsodyScreenState();
}

class _ProsodyScreenState extends State<ProsodyScreen>
    with WidgetsBindingObserver {
  late final PracticeSession s;
  final _script = TextEditingController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    s = widget.session ?? PracticeSession();
    s.addListener(_changed);
    if (widget.session == null && !kIsWeb) unawaited(s.initialize());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(s.audio.stopPlayback());
      if (s.busy) {
        unawaited(
          s.cancelCurrent(message: '화면을 벗어나 음성 작업을 멈췄어요. 이전 결과는 유지했어요.'),
        );
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

  Widget _card(List<Widget> children, {Color? color}) => Card(
    color: color ?? Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: Color(0xffdce5f2)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.5,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('높낮이 연습')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading('안드로이드 앱에서 연습해요'),
              const Text(
                '이 기능의 녹음과 대본 가이드 생성은 안드로이드 앱에서 사용할 수 있어요. 웹에서는 아래 목소리 흐름 테스트 주소로 연습할 수 있어요.',
                style: TextStyle(fontSize: 17, height: 1.8),
              ),
              const SizedBox(height: 16),
              const SelectableText(
                'https://voicemate-prosody-lab.choosu105832719.chatgpt.site/',
              ),
            ],
          ),
        ),
      );
    }
    final result = s.result, reference = s.reference;
    return Theme(
      data: Theme.of(context).copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(minimumSize: const Size(48, 50)),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            '높낮이 연습',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          backgroundColor: const Color(0xfff2f5fb),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: Text('연습용 시험 앱')),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 30),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '눈으로 보고,\n한 구간씩 연습해요.',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      '편한 목소리로 시작해 보세요.\n한 번에 똑같이 따라 하지 않아도 괜찮아요.',
                      style: TextStyle(fontSize: 16, height: 1.7),
                    ),
                    SizedBox(height: 18),
                  ],
                ),
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('준비된 문구')),
                  ButtonSegment(value: true, label: Text('내 대본')),
                ],
                selected: {s.usingScript},
                onSelectionChanged: s.busy
                    ? null
                    : (values) => s.setMode(values.first),
              ),
              const SizedBox(height: 12),
              if (s.usingScript)
                _card([
                  _heading('내가 할 말로 연습하기'),
                  TextField(
                    controller: _script,
                    enabled: !s.busy,
                    maxLength: 2000,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: '연습할 대본',
                      hintText: '안녕하세요. 오늘은 저희 프로젝트를 소개하겠습니다.',
                    ),
                    style: const TextStyle(fontSize: 17, height: 1.6),
                  ),
                  FilledButton(
                    onPressed: s.busy
                        ? null
                        : () => s.applyScript(_script.text),
                    child: const Text('대본으로 연습 준비'),
                  ),
                ]),
              _card([
                _heading('1. 가이드 보고 읽기'),
                if (s.phrases.isNotEmpty)
                  DropdownButtonFormField<int>(
                    key: ValueKey(
                      '${s.usingScript}-${s.index}-${s.phrases.join()}',
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
                Text(
                  s.phrase,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  reference?.source ?? '대본의 한국어 가이드를 먼저 만들어 주세요.',
                  style: const TextStyle(color: Color(0xff63748d), height: 1.6),
                ),
                if (s.usingScript) ...[
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: s.busy || s.phrases.isEmpty
                        ? null
                        : s.generateGuide,
                    icon: const Icon(Icons.graphic_eq),
                    label: Text(
                      reference == null ? '한국어 가이드 만들기' : '한국어 가이드 다시 만들기',
                    ),
                  ),
                  const Text(
                    '기기에 설치된 오프라인 한국어 음성을 사용해요.',
                    style: TextStyle(fontSize: 13, height: 1.8),
                  ),
                ],
                if (s.excerpt) ...[
                  const SizedBox(height: 12),
                  const Text(
                    '선택한 시간 구간만 연습 중이에요.',
                    style: TextStyle(fontWeight: FontWeight.w700, height: 1.7),
                  ),
                  OutlinedButton(
                    onPressed: s.busy ? null : s.leaveExcerpt,
                    child: const Text('전체 문장으로 돌아가기'),
                  ),
                ],
                const SizedBox(height: 14),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('높낮이')),
                    ButtonSegment(value: true, label: Text('소리 크기')),
                  ],
                  selected: {s.volume},
                  onSelectionChanged: (values) => s.setVolume(values.first),
                ),
                const SizedBox(height: 14),
                Text(
                  s.recording
                      ? '실시간 · 실제 경과 시간'
                      : result == null
                      ? '가이드 미리보기'
                      : '녹음 후 · 속도 맞춤',
                  style: TextStyle(
                    color: s.recording
                        ? const Color(0xffb64d32)
                        : const Color(0xff486b9f),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                ProsodyChart(
                  reference: reference?.analysis,
                  trace: s.trace,
                  volume: s.volume,
                  live: s.recording,
                  progress: s.recording
                      ? (s.liveTrace.isEmpty ? 0 : s.liveTrace.last.time)
                      : null,
                  domainSeconds: s.recording ? s.liveDomain : null,
                  scaleBound: s.recording
                      ? (s.volume ? s.levelBound : s.pitchBound)
                      : null,
                  selected: s.recording ? null : s.segment,
                ),
                if (s.recording)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      s.currentVoice
                          ? '● 내 목소리를 주황 선과 점으로 표시하고 있어요.'
                          : '○ 목소리를 기다리고 있어요. 확인되면 주황 점이 나타나요.',
                      style: TextStyle(
                        color: s.currentVoice
                            ? const Color(0xffb64d32)
                            : const Color(0xff68798f),
                        height: 1.6,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(s.recording ? '녹음 중' : '마이크 대기'),
                    Text(
                      '00:${s.seconds.floor().toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: s.recording
                      ? s.stopRecording
                      : s.busy || reference == null
                      ? null
                      : s.startRecording,
                  icon: Icon(
                    s.recording ? Icons.stop_rounded : Icons.mic_rounded,
                  ),
                  label: Text(s.recording ? '녹음 마치기' : '녹음 시작'),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: s.busy || reference == null
                          ? null
                          : s.playGuide,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('가이드 듣기 · 선택'),
                    ),
                    OutlinedButton(
                      onPressed: s.busy || reference == null ? null : s.demo,
                      child: const Text('녹음 없이 데모 보기'),
                    ),
                  ],
                ),
                if (s.phase == PracticePhase.generating ||
                    s.phase == PracticePhase.processing ||
                    s.phase == PracticePhase.loading) ...[
                  const SizedBox(height: 14),
                  const LinearProgressIndicator(),
                ],
                const SizedBox(height: 14),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    s.status,
                    style: const TextStyle(fontSize: 15, height: 1.7),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '최대 20초 · 마이크 권한은 녹음할 때 요청해요.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.7,
                    color: Color(0xff63748d),
                  ),
                ),
              ]),
              if (result != null && reference != null)
                _card([
                  _heading('2. 내 목소리를 함께 살펴봐요'),
                  if (result.demo)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text(
                        '합성 시험 신호 · 실제 사람의 녹음이 아니에요.',
                        style: TextStyle(color: Color(0xff94662d)),
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < result.summary.segments.length; i++)
                        ChoiceChip(
                          label: Text(
                            '${result.summary.segments[i].label}\n${practiceFeedback(reference.analysis, result.analysis, result.comparison, result.summary.segments[i], volume: s.volume).cardLabel}',
                          ),
                          selected: s.selected == i,
                          onSelected: s.busy ? null : (_) => s.selectRegion(i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (s.feedback case final PracticeFeedback f) ...[
                    Text(
                      f.title,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      f.observation,
                      style: const TextStyle(fontSize: 16, height: 1.7),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xffedf4ff),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        f.action,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          height: 1.7,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ExpansionTile(
                      title: const Text('측정값과 비교 방법'),
                      tilePadding: EdgeInsets.zero,
                      children: [
                        Text(
                          f.detail,
                          style: const TextStyle(fontSize: 14, height: 1.8),
                        ),
                        for (final part in result.summary.segments)
                          Padding(
                            padding: const EdgeInsets.only(top: 7),
                            child: Text(
                              '${part.label} 평균 차이 · 높낮이 ${part.pitchError?.toStringAsFixed(1) ?? '미측정'}반음 / 강약 ${part.levelError?.toStringAsFixed(1) ?? '미측정'}dB',
                              style: const TextStyle(fontSize: 13, height: 1.7),
                            ),
                          ),
                        const Text(
                          '시간 구간을 비교한 것이며, 단어나 음절을 자동으로 찾은 결과는 아니에요. 소리 크기는 상대값이에요.',
                          style: TextStyle(fontSize: 13, height: 1.7),
                        ),
                      ],
                    ),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: s.busy
                            ? null
                            : () => s.playGuide(region: true),
                        child: const Text('선택 구간의 가이드 듣기'),
                      ),
                      OutlinedButton(
                        onPressed: s.busy
                            ? null
                            : () => s.playUser(region: true),
                        child: const Text('선택 구간의 내 녹음 듣기'),
                      ),
                    ],
                  ),
                  if (!s.excerpt) ...[
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: s.busy ? null : s.practiceSelected,
                      child: const Text('이 구간만 다시 연습하기'),
                    ),
                  ],
                ]),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  '음성과 대본은 이 기기 안에서 처리해요. 재생을 위한 앱 임시 파일을 사용해요.\n가이드는 한 가지 읽기 예시이며, 말하기 실력이나 자연스러움을 채점하지 않아요.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.8,
                    color: Color(0xff68798f),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
