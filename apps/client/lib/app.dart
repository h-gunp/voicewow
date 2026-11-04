import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'app_theme.dart';
import 'audio/audio_port.dart';
import 'audio/unsupported_audio_port.dart'
    if (dart.library.js_interop) 'audio/web_audio_port.dart';
import 'session_controller.dart';
import 'screens/scenario_screen.dart';
import 'screens/meter_screen.dart';
import 'features/pronunciation/presentation/pronunciation_screen.dart';
import 'features/pronunciation/data/learning_store.dart';
import 'features/prosody/presentation/prosody_screen.dart';
import 'features/prosody/practice_session.dart';

class VoiceMateApp extends StatefulWidget {
  final AudioPort? audioPort;
  final TextScaler? textScaler;
  final bool startWithPronunciation;
  final bool startWithProsody;
  final PracticeSession? prosodySession;
  final LearningController? pronunciationLearning;
  const VoiceMateApp({
    super.key,
    this.audioPort,
    this.textScaler,
    this.startWithPronunciation = false,
    this.startWithProsody = false,
    this.prosodySession,
    this.pronunciationLearning,
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
  LearningController? pronunciationLearning;
  PracticeSession? prosody;
  @override
  void initState() {
    super.initState();
    section = widget.startWithProsody
        ? 2
        : widget.startWithPronunciation
        ? 1
        : 0;
    pronunciationLearning = widget.pronunciationLearning;
    if (section == 2) _prepareProsody();
    session = SessionController(widget.audioPort ?? createAudioPort());
    semantics = WidgetsBinding.instance.ensureSemantics();
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
      if (section == 0 && session.active) await session.stop();
      final currentProsody = prosody;
      if (section == 2 && currentProsody != null) {
        await currentProsody.audio.stopPlayback();
        await currentProsody.cancelCurrent();
      }
      if (!mounted) return;
      if (index == 2) _prepareProsody();
      if (mounted) setState(() => section = index);
    } finally {
      if (mounted) setState(() => changingSection = false);
    }
  }

  @override
  void dispose() {
    if (widget.pronunciationLearning == null) pronunciationLearning?.dispose();
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
        textScaler: widget.textScaler ?? MediaQuery.textScalerOf(context),
      ),
      child: child!,
    ),
    home: Scaffold(
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Color(0x1224467a),
              blurRadius: 24,
              offset: Offset(0, -4),
            ),
          ],
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
          child: section == 2
              ? ProsodyScreen(
                  session: prosody!,
                  onExit: () => _selectSection(0),
                )
              : section == 1
              ? PronunciationScreen(
                  learning: pronunciationLearning ??= LearningController(
                    PreferencesLearningStore(),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth > 600;
                    return AppBackdrop(
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
                                vertical: wide ? 32 : 8,
                                horizontal: wide ? 24 : 20,
                              ),
                              child: SizedBox(
                                width: 560,
                                child: Material(
                                  color: Colors.transparent,
                                  child: ListenableBuilder(
                                    listenable: session,
                                    builder: (context, _) =>
                                        meter && session.scenario != null
                                        ? GlassSurface(
                                            child: MeterScreen(
                                              session: session,
                                              onBack: () {
                                                setState(() => meter = false);
                                                session.stop();
                                              },
                                            ),
                                          )
                                        : ScenarioScreen(
                                            session: session,
                                            onStart: () {
                                              setState(() => meter = true);
                                              session.start();
                                            },
                                          ),
                                  ),
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
      ),
    ),
  );
}
