import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';

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
  const ProsodyWebFrame({super.key, this.onExit});
  final Future<void> Function()? onExit;

  @override
  State<ProsodyWebFrame> createState() => _ProsodyWebFrameState();
}

class _ProsodyWebFrameState extends State<ProsodyWebFrame>
    with WidgetsBindingObserver {
  late final Uri _source;
  late final String _origin;
  late final JSFunction _messages;
  _Frame? _frame;
  ProsodyFrameLifecycle? _lifecycle;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _source = embeddedProsodyUri(Uri.base);
    _origin = Uri.base.origin;
    _messages = ((JSObject raw) => _onMessage(_MessageEvent(raw))).toJS;
    _hostWindow.addEventListener('message', _messages);
    WidgetsBinding.instance.addObserver(this);
  }

  void _attach(Object element) {
    final frame = _Frame(element as JSObject);
    final lifecycle = ProsodyFrameLifecycle(_BrowserFramePort(frame, _origin));
    if (!mounted) {
      lifecycle.dispose();
      return;
    }
    _frame = frame;
    _lifecycle = lifecycle;
    frame.title = 'VoiceMate 높낮이 연습';
    frame.allow = "microphone 'self'";
    frame.setAttribute(
      'style',
      'border:0;width:100%;height:100%;display:block;background:#ffffff;',
    );
    frame.src = _source.toString();
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
    WidgetsBinding.instance.removeObserver(this);
    _hostWindow.removeEventListener('message', _messages);
    _lifecycle?.dispose();
    _frame = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
    key: const Key('prosody-web-frame'),
    tagName: 'iframe',
    onElementCreated: _attach,
  );
}
