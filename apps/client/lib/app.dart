import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'app_theme.dart';
import 'text_size_preferences.dart';
import 'widgets/training_guide.dart';
import 'audio/audio_port.dart';
import 'audio/unsupported_audio_port.dart'
    if (dart.library.js_interop) 'audio/web_audio_port.dart';
import 'session_controller.dart';
import 'screens/scenario_screen.dart';
import 'screens/meter_screen.dart';
import 'features/pronunciation/presentation/pronunciation_screen.dart';
import 'features/pronunciation/data/learning_store.dart';
import 'features/pronunciation/data/speech_player.dart';
import 'features/pronunciation/data/pronunciation_recorder.dart';
import 'features/prosody/presentation/prosody_screen.dart';
import 'features/prosody/practice_session.dart';

class VoiceMateApp extends StatefulWidget {
  final AudioPort? audioPort;
  final TextScaler? textScaler;
  final TextSizeStore? textSizeStore;
  final bool startWithPronunciation;
  final bool startWithProsody;
  final PracticeSession? prosodySession;
  final LearningController? pronunciationLearning;
  final SpeechPlayer? pronunciationSpeech;
  final PronunciationRecorder? pronunciationRecorder;
  const VoiceMateApp({
    super.key,
    this.audioPort,
    this.textScaler,
    this.textSizeStore,
    this.startWithPronunciation = false,
    this.startWithProsody = false,
    this.prosodySession,
    this.pronunciationLearning,
    this.pronunciationSpeech,
    this.pronunciationRecorder,
  });
  @override
  State<VoiceMateApp> createState() => _VoiceMateAppState();
}

class _VoiceMateAppState extends State<VoiceMateApp> {
  late final SessionController session;
  late final SemanticsHandle semantics;
  bool meter = false;
  late int section;
  bool changingSection = false;
  bool _showingGuide = false;
  LearningController? pronunciationLearning;
  SpeechPlayer? pronunciationSpeech;
  PronunciationRecorder? pronunciationRecorder;
  PracticeSession? prosody;
  late final TextSizeStore _textSizeStore;
  AppTextSize _textSize = AppTextSize.basic;
  int _textSizeRevision = 0;
  bool _textSizeStorageFailed = false;
  Future<void> _textSizeSave = Future<void>.value();
  @override
  void initState() {
    super.initState();
    section = widget.startWithProsody
        ? 2
        : widget.startWithPronunciation
        ? 1
        : 0;
    pronunciationLearning = widget.pronunciationLearning;
    pronunciationSpeech = widget.pronunciationSpeech;
    pronunciationRecorder = widget.pronunciationRecorder;
    if (section == 2) _prepareProsody();
    session = SessionController(widget.audioPort ?? createAudioPort());
    semantics = WidgetsBinding.instance.ensureSemantics();
    _textSizeStore = widget.textSizeStore ?? PreferencesTextSizeStore();
    unawaited(_loadTextSize());
  }

  Future<void> _loadTextSize() async {
    try {
      final saved = await _textSizeStore.load();
      // A late read must not undo a choice already made on this screen.
      if (mounted && _textSizeRevision == 0) setState(() => _textSize = saved);
    } catch (_) {
      if (mounted && _textSizeRevision == 0) {
        setState(() => _textSizeStorageFailed = true);
      }
    }
  }

  void _setTextSize(AppTextSize size) {
    final revision = ++_textSizeRevision;
    setState(() {
      _textSize = size;
      _textSizeStorageFailed = false;
    });
    // Keep quick successive choices in order on asynchronous storage.
    _textSizeSave = _textSizeSave.then((_) async {
      var failed = false;
      try {
        await _textSizeStore.save(size);
      } catch (_) {
        failed = true;
      }
      if (mounted && revision == _textSizeRevision) {
        setState(() => _textSizeStorageFailed = failed);
      }
    });
  }

  void _showTextSize(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SingleChildScrollView(
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('글자 크기', style: pageTitle),
                const SizedBox(height: 8),
                const Text('기기의 글자 크기 설정에 맞춰 추가로 확대한다.', style: bodyCopy),
                const SizedBox(height: 12),
                for (final size in AppTextSize.values)
                  Semantics(
                    checked: size == _textSize,
                    child: ListTile(
                      key: Key('text-size-${size.name}'),
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        size == _textSize
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                      ),
                      title: Text(size.label),
                      selected: size == _textSize,
                      onTap: () {
                        _setTextSize(size);
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                  ),
                if (_textSizeStorageFailed)
                  const Text(
                    '글자 크기를 저장하지 못했다. 다음 실행에서 다시 선택해야 할 수 있다.',
                    style: bodyCopy,
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('닫기'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showTrainingGuide(BuildContext context) async {
    if (changingSection) return;
    setState(() => changingSection = true);
    try {
      await _stopCurrentSection(forGuide: true);
    } finally {
      if (mounted) setState(() => changingSection = false);
    }
    if (!mounted || !context.mounted) return;
    setState(() => _showingGuide = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (guideContext) => TrainingGuideScreen(
            onSelectSection: (index) {
              Navigator.of(guideContext).pop();
              unawaited(_selectSection(index));
            },
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _showingGuide = false);
    }
  }

  PracticeSession _prepareProsody() {
    if (prosody != null) return prosody!;
    final next = widget.prosodySession ?? PracticeSession();
    prosody = next;
    if (widget.prosodySession == null && !kIsWeb) {
      unawaited(next.initialize());
    }
    return next;
  }

  Future<void> _selectSection(int index) async {
    if (changingSection || index == section || index < 0 || index > 2) return;
    setState(() => changingSection = true);
    try {
      await _stopCurrentSection();
      if (!mounted) return;
      if (index == 2) _prepareProsody();
      if (mounted) setState(() => section = index);
    } finally {
      if (mounted) setState(() => changingSection = false);
    }
  }

  Future<void> _stopCurrentSection({bool forGuide = false}) async {
    if (section == 0 && session.active) await session.stop();
    if (section == 1) {
      await pronunciationSpeech?.stop();
      if (!forGuide) await pronunciationRecorder?.cancel();
    }
    final currentProsody = prosody;
    if (section == 2 && currentProsody != null) {
      await currentProsody.audio.stopPlayback();
      await currentProsody.cancelCurrent();
    }
  }

  @override
  void dispose() {
    if (widget.pronunciationLearning == null) pronunciationLearning?.dispose();
    if (widget.pronunciationSpeech == null) {
      unawaited(pronunciationSpeech?.dispose() ?? Future<void>.value());
    }
    if (widget.pronunciationRecorder == null) {
      unawaited(pronunciationRecorder?.dispose() ?? Future<void>.value());
    }
    if (widget.prosodySession == null) prosody?.dispose();
    session.dispose();
    semantics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'VoiceMate',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: _AppTextScaler(
          widget.textScaler ?? MediaQuery.textScalerOf(context),
          _textSize.factor,
        ),
      ),
      child: child!,
    ),
    home: Scaffold(
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: line)),
        ),
        child: NavigationBar(
          selectedIndex: section,
          onDestinationSelected: changingSection ? null : _selectSection,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.graphic_eq), label: '음량 측정'),
            NavigationDestination(
              key: Key('open-pronunciation'),
              icon: Icon(Icons.auto_stories_outlined),
              selectedIcon: Icon(Icons.auto_stories),
              label: '발음 훈련',
            ),
            NavigationDestination(
              key: Key('open-prosody'),
              icon: Icon(Icons.multiline_chart_outlined),
              selectedIcon: Icon(Icons.multiline_chart),
              label: '높낮이 연습',
            ),
          ],
        ),
      ),
      body: AbsorbPointer(
        absorbing: changingSection,
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: line)),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Builder(
                  builder: (context) => Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 12,
                    children: [
                      Tooltip(
                        message: '글자 크기: ${_textSize.label}',
                        child: TextButton.icon(
                          key: const Key('text-size-control'),
                          onPressed: () => _showTextSize(context),
                          icon: const Icon(Icons.text_fields),
                          label: const Text('글자 크기'),
                        ),
                      ),
                      TextButton.icon(
                        key: const Key('open-training-guide'),
                        onPressed: () => _showTrainingGuide(context),
                        icon: const Icon(Icons.help_outline),
                        label: const Text('도움말'),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: section == 2
                    ? ProsodyScreen(
                        session: prosody!,
                        suspended: _showingGuide,
                        onExit: () => _selectSection(0),
                      )
                    : section == 1
                    ? PronunciationScreen(
                        suspended: _showingGuide,
                        learning: pronunciationLearning ??= LearningController(
                          PreferencesLearningStore(),
                        ),
                        speech: pronunciationSpeech ??= DeviceSpeechPlayer(
                          localOnly: true,
                        ),
                        recorder: pronunciationRecorder ??=
                            createPronunciationRecorder(),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth > 800;
                          return ColoredBox(
                            color: canvas,
                            child: SingleChildScrollView(
                              key: ValueKey(meter),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      vertical: wide ? 36 : 20,
                                      horizontal: wide ? 40 : 20,
                                    ),
                                    child: SizedBox(
                                      width: 720,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.only(
                                              bottom: 18,
                                            ),
                                            decoration: const BoxDecoration(
                                              border: Border(
                                                bottom: BorderSide(color: line),
                                              ),
                                            ),
                                            child: const Wrap(
                                              alignment:
                                                  WrapAlignment.spaceBetween,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              spacing: 24,
                                              runSpacing: 8,
                                              children: [
                                                Text(
                                                  'VoiceMate',
                                                  style: TextStyle(
                                                    fontSize: 21,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: -.7,
                                                  ),
                                                ),
                                                Text(
                                                  '목소리 입력 · 실험 버전',
                                                  style: smallCopy,
                                                ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(height: wide ? 40 : 28),
                                          if (!meter)
                                            Align(
                                              alignment: Alignment.centerLeft,
                                              child: TextButton.icon(
                                                key: const Key(
                                                  'open-training-guide-intro',
                                                ),
                                                onPressed: () =>
                                                    _showTrainingGuide(context),
                                                icon: const Icon(
                                                  Icons.self_improvement,
                                                ),
                                                label: const Text(
                                                  '처음이라면 준비 안내',
                                                ),
                                              ),
                                            ),
                                          Material(
                                            color: Colors.transparent,
                                            child: ListenableBuilder(
                                              listenable: session,
                                              builder: (context, _) =>
                                                  meter &&
                                                      session.scenario != null
                                                  ? MeterScreen(
                                                      session: session,
                                                      onBack: () {
                                                        setState(
                                                          () => meter = false,
                                                        );
                                                        session.stop();
                                                      },
                                                    )
                                                  : ScenarioScreen(
                                                      session: session,
                                                      onStart: () {
                                                        setState(
                                                          () => meter = true,
                                                        );
                                                        session.start();
                                                      },
                                                    ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
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

class _AppTextScaler extends TextScaler {
  const _AppTextScaler(this.system, this.factor);
  final TextScaler system;
  final double factor;

  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;

  @override
  double get textScaleFactor => scale(14) / 14;
}
