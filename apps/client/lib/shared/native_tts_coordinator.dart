import 'dart:async';

import 'package:flutter/services.dart';

enum NativeTtsKind { speech, synthesis }

/// Serializes the plugin's process-wide, ID-less Android callbacks.
class NativeTtsCoordinator {
  static final shared = NativeTtsCoordinator();
  static const _channel = MethodChannel('flutter_tts');
  NativeTtsLease? _current;

  Future<NativeTtsLease?> acquire(
    NativeTtsKind kind, {
    Duration timeout = const Duration(seconds: 1),
    Future<void>? cancelled,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (_current != null) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) return null;
      final previous = _current!;
      final ready = await Future.any<bool>([
        previous.done.future.then((_) => true),
        if (cancelled != null) cancelled.then((_) => false),
        Future<bool>.delayed(remaining, () => false),
      ]);
      if (!ready) return null;
    }
    final lease = NativeTtsLease._(this, kind);
    _current = lease;
    return lease;
  }

  void installHandler(
    NativeTtsLease lease,
    Future<dynamic> Function(MethodCall) handler,
  ) {
    if (!identical(_current, lease)) return;
    lease.handler = handler;
    _channel.setMethodCallHandler(dispatch);
  }

  Future<dynamic> dispatch(MethodCall call) async {
    final lease = _current;
    if (lease == null) return;
    final terminal =
        lease.issued &&
        (lease.kind == NativeTtsKind.speech
            ? const {
                'speak.onComplete',
                'speak.onCancel',
                'speak.onError',
              }.contains(call.method)
            : const {
                'synth.onComplete',
                'synth.onError',
                'speak.onCancel',
              }.contains(call.method));
    try {
      await lease.handler?.call(call);
    } finally {
      if (terminal && identical(_current, lease)) _release(lease);
    }
  }

  void _release(NativeTtsLease lease) {
    if (!identical(_current, lease)) return;
    _current = null;
    lease.done.complete();
  }
}

class NativeTtsLease {
  NativeTtsLease._(this._coordinator, this.kind);
  final NativeTtsCoordinator _coordinator;
  final NativeTtsKind kind;
  final done = Completer<void>();
  Future<dynamic> Function(MethodCall)? handler;
  bool issued = false;
  bool get isCurrent => identical(_coordinator._current, this);
  void releaseUnissued() {
    if (!issued) _coordinator._release(this);
  }

  // The plugin explicitly rejected the queue request; no utterance exists.
  void rejectIssue() => _coordinator._release(this);
}
