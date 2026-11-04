import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/app_theme.dart';
import 'package:voicemate/features/pronunciation/data/speech_player.dart';
import 'package:voicemate/features/pronunciation/presentation/speech_controls.dart';

class ControlledSpeech implements SpeechPlayer, SpeechPlaybackSource {
  final state = ValueNotifier(const SpeechPlaybackState());
  Completer<SpeechResult>? pending;
  int request = 0;
  int calls = 0;
  int stops = 0;
  bool lastSlow = false;
  @override
  ValueListenable<SpeechPlaybackState> get playback => state;
  @override
  Future<SpeechResult> speak(String text, {bool slow = false}) {
    calls++;
    request++;
    lastSlow = slow;
    pending = Completer<SpeechResult>();
    state.value = SpeechPlaybackState(
      phase: SpeechPhase.preparing,
      requestId: request,
    );
    return pending!.future;
  }

  void start() {
    state.value = SpeechPlaybackState(
      phase: SpeechPhase.playing,
      requestId: request,
      result: SpeechResult.started,
    );
    if (!pending!.isCompleted) pending!.complete(SpeechResult.started);
  }

  void complete() => state.value = SpeechPlaybackState(requestId: request);
  void fail() {
    state.value = SpeechPlaybackState(
      requestId: request,
      result: SpeechResult.unavailable,
    );
    if (!pending!.isCompleted) pending!.complete(SpeechResult.unavailable);
  }

  @override
  Future<void> stop() async {
    stops++;
    state.value = SpeechPlaybackState(
      requestId: request,
      result: SpeechResult.cancelled,
    );
    if (pending != null && !pending!.isCompleted)
      pending!.complete(SpeechResult.cancelled);
  }

  @override
  Future<void> dispose() async {
    await stop();
    state.dispose();
  }
}

void main() {
  late ControlledSpeech player;
  late SpeechPlaybackController playback;
  final owner = Object();
  const normal = Key('normal-voice');
  const slow = Key('slow-voice');

  setUp(() {
    player = ControlledSpeech();
    playback = SpeechPlaybackController(player);
  });

  tearDown(() async {
    playback.dispose();
    await player.dispose();
  });

  Future<void> open(
    WidgetTester tester, {
    bool enabled = true,
    bool secondOwner = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Column(
            children: [
              SpeechControls(
                playback: playback,
                text: '같이 가요',
                owner: owner,
                normalKey: normal,
                slowKey: slow,
                enabled: enabled,
              ),
              if (secondOwner)
                SpeechControls(
                  playback: playback,
                  text: '같이 가요',
                  owner: 'other-view',
                  normalKey: const Key('other-normal'),
                  slowKey: const Key('other-slow'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  OutlinedButton button(WidgetTester tester, Key key) =>
      tester.widget(find.byKey(key));

  testWidgets(
    'both controls are gray during preparation, blue active only after start, then ready on completion',
    (tester) async {
      await open(tester);
      expect(button(tester, normal).onPressed, isNotNull);
      expect(button(tester, slow).onPressed, isNotNull);
      await tester.tap(find.byKey(normal));
      await tester.pump();
      expect(find.text('음성 준비 중…'), findsOneWidget);
      expect(find.text('재생 중 · 정지'), findsNothing);
      expect(button(tester, normal).onPressed, isNull);
      expect(button(tester, slow).onPressed, isNull);
      expect(
        button(
          tester,
          normal,
        ).style!.backgroundColor!.resolve({WidgetState.disabled}),
        const Color(0xffe6e8eb),
      );
      expect(
        button(
          tester,
          slow,
        ).style!.backgroundColor!.resolve({WidgetState.disabled}),
        const Color(0xffe6e8eb),
      );

      player.start();
      await tester.pump();
      expect(find.text('음성 준비 중…'), findsNothing);
      expect(find.text('재생 중 · 정지'), findsOneWidget);
      expect(button(tester, normal).onPressed, isNotNull);
      expect(button(tester, slow).onPressed, isNull);
      expect(button(tester, normal).style!.backgroundColor!.resolve({}), blue);
      player.complete();
      await tester.pump();
      expect(find.text('재생 중 · 정지'), findsNothing);
      expect(button(tester, normal).onPressed, isNotNull);
      expect(button(tester, slow).onPressed, isNotNull);
      expect(find.text('예시 듣기'), findsOneWidget);
      expect(find.text('천천히 듣기'), findsOneWidget);
    },
  );

  testWidgets(
    'slow control becomes the stop control and cancels the real player',
    (tester) async {
      await open(tester);
      await tester.tap(find.byKey(slow));
      await tester.pump();
      expect(player.lastSlow, isTrue);
      expect(
        find.descendant(of: find.byKey(slow), matching: find.text('음성 준비 중…')),
        findsOneWidget,
      );
      player.start();
      await tester.pump();
      expect(button(tester, normal).onPressed, isNull);
      expect(button(tester, slow).onPressed, isNotNull);
      expect(button(tester, slow).style!.backgroundColor!.resolve({}), blue);
      await tester.tap(find.byKey(slow));
      await tester.pump();
      expect(player.stops, 1);
      expect(playback.phase, SpeechPhase.ready);
      expect(button(tester, normal).onPressed, isNotNull);
      expect(button(tester, slow).onPressed, isNotNull);
      expect(find.textContaining('재생할 수 없어요'), findsNothing);
    },
  );

  testWidgets(
    'all views share the busy state and other owners cannot stop its speech',
    (tester) async {
      await open(tester, secondOwner: true);
      await tester.tap(find.byKey(normal));
      await tester.pump();
      expect(button(tester, const Key('other-normal')).onPressed, isNull);
      expect(button(tester, const Key('other-slow')).onPressed, isNull);
      await playback.stop(owner: 'other-view');
      expect(player.stops, 0);
      expect(playback.phase, SpeechPhase.preparing);
      player.start();
      await tester.pump();
      expect(button(tester, const Key('other-normal')).onPressed, isNull);
      expect(find.text('재생 중 · 정지'), findsOneWidget);
      player.complete();
      await tester.pump();
      expect(button(tester, const Key('other-normal')).onPressed, isNotNull);
    },
  );

  testWidgets(
    'rapid taps cannot queue duplicate utterances before the next frame',
    (tester) async {
      await open(tester);
      await tester.tap(find.byKey(normal));
      await tester.tap(find.byKey(slow));
      await tester.pump();
      expect(player.calls, 1);
      await playback.stop();
      await tester.pump();
    },
  );

  testWidgets(
    'a platform error during playback restores ready controls and reports it once',
    (tester) async {
      await open(tester);
      await tester.tap(find.byKey(normal));
      player.start();
      await tester.pump();
      player.fail();
      await tester.pump();
      await tester.pump();
      expect(button(tester, normal).onPressed, isNotNull);
      expect(button(tester, slow).onPressed, isNotNull);
      expect(find.textContaining('한국어 예시 음성을 재생할 수 없어요'), findsOneWidget);
      expect(playback.failureCount, 1);
    },
  );

  testWidgets('disabled or disposed controls do not submit new playback', (
    tester,
  ) async {
    await open(tester, enabled: false);
    expect(button(tester, normal).onPressed, isNull);
    expect(button(tester, slow).onPressed, isNull);
    expect(player.calls, 0);
    playback.dispose();
    await playback.stop(owner: owner);
    expect(await playback.play('같이 가요', owner: owner), SpeechResult.cancelled);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
