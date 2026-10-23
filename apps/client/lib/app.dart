import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'app_theme.dart';
import 'audio/audio_port.dart';
import 'audio/unsupported_audio_port.dart'
    if (dart.library.js_interop) 'audio/web_audio_port.dart';
import 'session_controller.dart';
import 'screens/scenario_screen.dart';
import 'screens/meter_screen.dart';

class VoiceMateApp extends StatefulWidget {
  final AudioPort? audioPort;
  final TextScaler? textScaler;
  const VoiceMateApp({super.key, this.audioPort, this.textScaler});
  @override
  State<VoiceMateApp> createState() => _VoiceMateAppState();
}

class _VoiceMateAppState extends State<VoiceMateApp> {
  late final SessionController session;
  late final SemanticsHandle semantics;
  bool meter = false;
  @override
  void initState() {
    super.initState();
    session = SessionController(widget.audioPort ?? createAudioPort());
    semantics = WidgetsBinding.instance.ensureSemantics();
  }

  @override
  void dispose() {
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
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 600;
            return ColoredBox(
              color: wide ? const Color(0xffeef1f3) : canvas,
              child: SingleChildScrollView(
                key: ValueKey(meter),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: wide ? 32 : 8,
                        horizontal: wide ? 24 : 12,
                      ),
                      child: Container(
                        width: 460,
                        padding: EdgeInsets.all(wide ? 28 : 16),
                        decoration: BoxDecoration(
                          color: canvas,
                          borderRadius: BorderRadius.circular(28),
                          border: wide ? Border.all(color: line) : null,
                        ),
                        child: Material(
                          color: canvas,
                          child: ListenableBuilder(
                            listenable: session,
                            builder: (context, _) =>
                                meter && session.scenario != null
                                ? MeterScreen(
                                    session: session,
                                    onBack: () {
                                      setState(() => meter = false);
                                      session.stop();
                                    },
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
  );
}
