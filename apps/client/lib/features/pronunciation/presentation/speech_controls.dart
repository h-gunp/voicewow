import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../app_theme.dart';
import '../data/speech_player.dart';

export '../data/speech_player.dart' show SpeechPhase;

/// One controller serves all pronunciation views. Owner identity prevents an
/// old view's disposal from stopping another view's new utterance.
class SpeechPlaybackController extends ChangeNotifier {
  final SpeechPlayer player;
  ValueListenable<SpeechPlaybackState>? _source;
  SpeechPhase _phase = SpeechPhase.ready;
  Object? _owner;
  bool _slow = false;
  int _generation = 0;
  int _failures = 0;
  int? _failedRequest;
  Object? _failureOwner;
  bool _disposed = false;

  SpeechPlaybackController(this.player) {
    if (player is SpeechPlaybackSource) {
      _source = (player as SpeechPlaybackSource).playback;
      _phase = _source!.value.phase;
      _source!.addListener(_onPlaybackChanged);
    }
  }

  SpeechPhase get phase => _phase;
  Object? get owner => _owner;
  bool get slow => _slow;
  int get failureCount => _failures;
  Object? get failureOwner => _failureOwner;

  void _onPlaybackChanged() {
    if (_disposed) return;
    final next = _source!.value;
    _phase = next.phase;
    if (next.phase == SpeechPhase.ready &&
        next.result == SpeechResult.unavailable &&
        next.requestId != _failedRequest &&
        _owner != null) {
      _failedRequest = next.requestId;
      _failureOwner = _owner;
      _failures++;
    }
    notifyListeners();
  }

  Future<SpeechResult> play(
    String text, {
    required Object owner,
    bool slow = false,
  }) async {
    if (_disposed || _phase != SpeechPhase.ready) return SpeechResult.cancelled;
    final generation = ++_generation;
    _owner = owner;
    _slow = slow;
    _phase = SpeechPhase.preparing;
    notifyListeners();
    SpeechResult outcome;
    try {
      outcome = await player.speak(text, slow: slow);
    } catch (_) {
      outcome = SpeechResult.unavailable;
    }
    if (_disposed || generation != _generation) return SpeechResult.cancelled;
    if (_source == null ||
        (outcome != SpeechResult.started && _phase == SpeechPhase.preparing)) {
      // A fake/player without lifecycle events cannot confirm actual playback
      // or its end. Never manufacture a playing animation from an ack alone.
      _phase = SpeechPhase.ready;
      if (outcome == SpeechResult.unavailable) {
        _failureOwner = owner;
        _failures++;
      }
      notifyListeners();
    }
    return outcome;
  }

  Future<void> stop({Object? owner}) async {
    if (_disposed || (owner != null && owner != _owner)) return;
    ++_generation;
    _owner = null;
    _phase = SpeechPhase.ready;
    notifyListeners();
    try {
      await player.stop();
    } catch (_) {
      // Cancellation must restore controls even when the engine is unavailable.
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _source?.removeListener(_onPlaybackChanged);
    super.dispose();
  }
}

class SpeechControls extends StatefulWidget {
  final SpeechPlaybackController playback;
  final String text;
  final Object owner;
  final Key? normalKey;
  final Key? slowKey;
  final String normalLabel;
  final String slowLabel;
  final bool enabled;

  const SpeechControls({
    super.key,
    required this.playback,
    required this.text,
    required this.owner,
    this.normalKey,
    this.slowKey,
    this.normalLabel = '예시 듣기',
    this.slowLabel = '천천히 듣기',
    this.enabled = true,
  });

  @override
  State<SpeechControls> createState() => _SpeechControlsState();
}

class _SpeechControlsState extends State<SpeechControls> {
  late int _seenFailures;

  @override
  void initState() {
    super.initState();
    _seenFailures = widget.playback.failureCount;
    widget.playback.addListener(_onPlaybackChanged);
  }

  @override
  void didUpdateWidget(covariant SpeechControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playback != widget.playback) {
      oldWidget.playback.removeListener(_onPlaybackChanged);
      _seenFailures = widget.playback.failureCount;
      widget.playback.addListener(_onPlaybackChanged);
    }
  }

  void _onPlaybackChanged() {
    final playback = widget.playback;
    if (_seenFailures == playback.failureCount) return;
    _seenFailures = playback.failureCount;
    if (playback.failureOwner != widget.owner || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || playback.failureOwner != widget.owner) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('한국어 예시 음성을 재생할 수 없어요. 기기의 한국어 음성 설정을 확인해 주세요.'),
        ),
      );
    });
  }

  @override
  void dispose() {
    widget.playback.removeListener(_onPlaybackChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.playback,
    builder: (context, _) => Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [_button(false), _button(true)],
    ),
  );

  Widget _button(bool slow) {
    final playback = widget.playback;
    final preparing = playback.phase == SpeechPhase.preparing;
    final playing = playback.phase == SpeechPhase.playing;
    final selected = playback.owner == widget.owner && playback.slow == slow;
    final active = playing && selected;
    final available =
        widget.enabled && (playback.phase == SpeechPhase.ready || active);
    final label = selected && preparing
        ? '음성 준비 중…'
        : active
        ? '재생 중 · 정지'
        : slow
        ? widget.slowLabel
        : widget.normalLabel;
    return Semantics(
      liveRegion: selected && (preparing || playing),
      child: OutlinedButton.icon(
        key: slow ? widget.slowKey : widget.normalKey,
        onPressed: !available
            ? null
            : active
            ? () => unawaited(playback.stop(owner: widget.owner))
            : () => unawaited(
                playback.play(widget.text, owner: widget.owner, slow: slow),
              ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          foregroundColor: active ? Colors.white : ink,
          backgroundColor: active ? blue : Colors.white,
          disabledForegroundColor: const Color(0xff6c737c),
          disabledBackgroundColor: const Color(0xffe6e8eb),
          side: BorderSide(color: active ? blue : line),
        ),
        icon: Icon(
          active
              ? Icons.stop_rounded
              : slow
              ? Icons.slow_motion_video_rounded
              : Icons.volume_up_outlined,
          size: 20,
        ),
        label: Text(label),
      ),
    );
  }
}
