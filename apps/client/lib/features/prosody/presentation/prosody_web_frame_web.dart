import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';

import 'prosody_frame_shell.dart';
import 'prosody_web_frame_contract.dart';

@JS('window')
external _HostWindow get _hostWindow;

@JS()
extension type _HostWindow(JSObject _) implements JSObject {
  external void addEventListener(String type, JSFunction listener);
  external void removeEventListener(String type, JSFunction listener);
}

@JS()
extension type _Frame(JSObject _) implements JSObject {
  external set src(String value);
  external set title(String value);
  external set allow(String value);
  external _ChildWindow? get contentWindow;
  external void setAttribute(String name, String value);
  external void remove();
}

@JS()
extension type _ChildWindow(JSObject _) implements JSObject {
  external _Location get location;
  external JSFunction? get voiceMateProsodyCleanup;
  external void postMessage(JSAny? message, String targetOrigin);
}

@JS()
extension type _Location(JSObject _) implements JSObject {
  external String get origin;
}

@JS()
extension type _MessageEvent(JSObject _) implements JSObject {
  external String get origin;
  external _ChildWindow? get source;
  external JSAny? get data;
}

class _BrowserFramePort implements ProsodyFramePort {
  _BrowserFramePort(this.frame, this.origin);
  final _Frame frame;
  final String origin;

  @override
  void postCleanup() {
    frame.contentWindow?.postMessage(
      {'type': prosodyCleanupMessage}.jsify(),
      origin,
    );
  }

  @override
  void stopSameOriginAudio() {
    final child = frame.contentWindow;
    if (child == null || child.location.origin != origin) return;
    child.voiceMateProsodyCleanup?.callAsFunction(child);
  }

  @override
  void remove() {
    // Unload the browsing context as a fallback when its cleanup hook was not
    // installed, then remove the element immediately on leaving this tab.
    try {
      frame.src = 'about:blank';
    } finally {
      frame.remove();
    }
  }
}

/// Hosts only the bundled, same-origin web practice page. Constructing or
/// attaching this widget does not request a microphone, synthesize or play audio.
class ProsodyWebFrame extends StatefulWidget {
  const ProsodyWebFrame({super.key, this.onExit, this.suspended = false});
  final Future<void> Function()? onExit;
  final bool suspended;

  @override
  State<ProsodyWebFrame> createState() => _ProsodyWebFrameState();
}

class _ProsodyWebFrameState extends State<ProsodyWebFrame>
    with WidgetsBindingObserver {
  late final String _origin;
  late final JSFunction _messages;
  _Frame? _frame;
  ProsodyFrameLifecycle? _lifecycle;
  bool _exiting = false;
  bool _ready = false;
  String? _loadIssue;
  Timer? _loadTimer;
  int _attempt = 0;
  double _textScale = 1;

  @override
  void initState() {
    super.initState();
    _origin = Uri.base.origin;
    _messages = ((JSObject raw) => _onMessage(_MessageEvent(raw))).toJS;
    _hostWindow.addEventListener('message', _messages);
    WidgetsBinding.instance.addObserver(this);
    _startDeadline();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    if (scale == _textScale) return;
    _textScale = scale;
    _sendTextScale();
  }

  @override
  void didUpdateWidget(covariant ProsodyWebFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.suspended && !oldWidget.suspended) _lifecycle?.stopAudio();
  }

  void _sendTextScale() => _frame?.contentWindow?.postMessage(
    {'type': prosodyTextScaleMessage, 'scale': _textScale}.jsify(),
    _origin,
  );

  void _updateFrameVisibility() {
    // Hide the connected DOM, not Flutter's paint path that attaches it.
    _frame?.setAttribute(
      'style',
      'border:0;width:100%;height:100%;display:block;background:#ffffff;'
          'visibility:${_ready ? 'visible' : 'hidden'};'
          'pointer-events:${_ready ? 'auto' : 'none'};',
    );
    _frame?.setAttribute('aria-hidden', '${!_ready}');
    _frame?.setAttribute('tabindex', _ready ? '0' : '-1');
  }

  void _startDeadline() {
    _loadTimer?.cancel();
    _loadTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && !_ready) {
        setState(() => _loadIssue = '화면 준비에 시간이 걸린다. 잠시 기다리거나 다시 불러오면 된다.');
      }
    });
  }

  void _reload() {
    _lifecycle?.dispose();
    _lifecycle = null;
    _frame = null;
    setState(() {
      _attempt++;
      _ready = false;
      _loadIssue = null;
    });
    _startDeadline();
  }

  void _attach(Object element, int attempt) {
    final frame = _Frame(element as JSObject);
    final lifecycle = ProsodyFrameLifecycle(_BrowserFramePort(frame, _origin));
    if (!mounted || attempt != _attempt) {
      lifecycle.dispose();
      return;
    }
    _frame = frame;
    _lifecycle = lifecycle;
    frame.title = 'VoiceMate 높낮이 연습';
    frame.allow = "microphone 'self'";
    _updateFrameVisibility();
    frame.src = embeddedProsodyUri(Uri.base, textScale: _textScale).toString();
  }

  void _onMessage(_MessageEvent event) {
    final child = _frame?.contentWindow;
    // Check both origin and source before reading any payload or acting on it.
    if (event.origin != _origin || child == null || event.source != child)
      return;
    Object? data;
    try {
      data = event.data?.dartify();
    } catch (_) {
      return;
    }
    if (acceptsProsodyMessage(
      origin: event.origin,
      expectedOrigin: _origin,
      fromFrame: event.source == child,
      data: data,
      type: prosodyReadyMessage,
    )) {
      _loadTimer?.cancel();
      _sendTextScale();
      if (widget.suspended) _lifecycle?.stopAudio();
      setState(() {
        _ready = true;
        _loadIssue = null;
      });
      _updateFrameVisibility();
      return;
    }
    if (acceptsProsodyMessage(
      origin: event.origin,
      expectedOrigin: _origin,
      fromFrame: event.source == child,
      data: data,
      type: prosodyErrorMessage,
    )) {
      _loadTimer?.cancel();
      setState(() {
        _ready = false;
        _loadIssue = '높낮이 화면을 불러오지 못했다. 연결을 확인하고 다시 시도하면 된다.';
      });
      _updateFrameVisibility();
      return;
    }
    if (!acceptsProsodyExit(
      origin: event.origin,
      expectedOrigin: _origin,
      fromFrame: event.source == child,
      data: data,
    )) {
      return;
    }
    final exit = widget.onExit;
    if (_exiting || exit == null) return;
    _exiting = true;
    _lifecycle?.stopAudio();
    unawaited(
      exit().whenComplete(() {
        _exiting = false;
      }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _lifecycle?.stopAudio();
    }
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _hostWindow.removeEventListener('message', _messages);
    _lifecycle?.dispose();
    _frame = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final attempt = _attempt;
    return ProsodyFrameShell(
      ready: _ready,
      issue: _loadIssue,
      onRetry: _reload,
      frame: HtmlElementView.fromTagName(
        key: ValueKey('prosody-web-frame-$attempt'),
        tagName: 'iframe',
        onElementCreated: (element) => _attach(element, attempt),
      ),
    );
  }
}
