import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';

import 'prosody_frame_shell.dart';

@JS('voiceMateProsody')
external _ProsodyBridge? get _prosodyBridge;

extension type _ProsodyBridge(JSObject _) implements JSObject {
  external _Surface createSurface(JSObject host, JSFunction onExit);
}

extension type _Surface(JSObject _) implements JSObject {
  external JSPromise<JSAny?> get ready;
  external void pause();
  external void dispose();
  external void setTextScale(double value);
}

extension type _Host(JSObject _) implements JSObject {
  external _Style get style;
  external void setAttribute(String name, String value);
}

extension type _Style(JSObject _) implements JSObject {
  external void setProperty(String name, String value);
}

/// Mounts the bundled practice UI directly in this document; no child page.
class ProsodyWebSurface extends StatefulWidget {
  const ProsodyWebSurface({super.key, this.onExit, this.suspended = false});
  final Future<void> Function()? onExit;
  final bool suspended;

  @override
  State<ProsodyWebSurface> createState() => _ProsodyWebSurfaceState();
}

class _ProsodyWebSurfaceState extends State<ProsodyWebSurface>
    with WidgetsBindingObserver {
  _Host? _host;
  _Surface? _surface;
  bool _ready = false;
  bool _exiting = false;
  String? _loadIssue;
  Timer? _loadTimer;
  int _attempt = 0;
  double _textScale = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startDeadline();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    if (scale == _textScale) return;
    _textScale = scale;
    _surface?.setTextScale(scale);
  }

  @override
  void didUpdateWidget(covariant ProsodyWebSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.suspended && !oldWidget.suspended) _surface?.pause();
  }

  void _updateVisibility() {
    // Keep the platform view painted; hide only its connected DOM while loading.
    _host?.style.setProperty('visibility', _ready ? 'visible' : 'hidden');
    _host?.style.setProperty('pointer-events', _ready ? 'auto' : 'none');
    _host?.setAttribute('aria-hidden', '${!_ready}');
    _host?.setAttribute('tabindex', _ready ? '0' : '-1');
  }

  void _startDeadline() {
    _loadTimer?.cancel();
    _loadTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && !_ready) {
        setState(() => _loadIssue = '화면 준비에 시간이 걸린다. 잠시 기다리거나 다시 불러오면 된다.');
      }
    });
  }

  void _releaseSurface() {
    final previous = _surface;
    _surface = null;
    _host = null;
    previous?.dispose();
  }

  void _reload() {
    _attempt++;
    _releaseSurface();
    setState(() {
      _ready = false;
      _loadIssue = null;
    });
    _startDeadline();
  }

  Future<void> _attach(Object element, int attempt) async {
    if (!mounted || attempt != _attempt) return;
    final host = _Host(element as JSObject);
    _host = host;
    host.setAttribute(
      'style',
      'width:100%;height:100%;display:block;overflow:hidden;',
    );
    _updateVisibility();
    try {
      final bridge = _prosodyBridge;
      if (bridge == null) throw StateError('높낮이 모듈을 불러오지 못했다.');
      final surface = bridge.createSurface(
        host,
        (() {
          if (mounted && attempt == _attempt) unawaited(_exit());
        }).toJS,
      );
      _surface = surface;
      surface.setTextScale(_textScale);
      if (widget.suspended) surface.pause();
      await surface.ready.toDart;
      if (!mounted || attempt != _attempt || _surface != surface) return;
      _loadTimer?.cancel();
      surface.setTextScale(_textScale);
      if (widget.suspended) surface.pause();
      setState(() {
        _ready = true;
        _loadIssue = null;
      });
      _updateVisibility();
    } catch (_) {
      if (!mounted || attempt != _attempt) return;
      _loadTimer?.cancel();
      setState(() {
        _ready = false;
        _loadIssue = '높낮이 화면을 불러오지 못했다. 연결을 확인하고 다시 시도하면 된다.';
      });
      _updateVisibility();
    }
  }

  Future<void> _exit() async {
    final exit = widget.onExit;
    if (_exiting || exit == null) return;
    _exiting = true;
    _surface?.pause();
    try {
      await exit();
    } finally {
      _exiting = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _surface?.pause();
    }
  }

  @override
  void dispose() {
    _attempt++;
    _loadTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _releaseSurface();
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
        key: ValueKey('prosody-web-surface-$attempt'),
        tagName: 'div',
        onElementCreated: (element) => unawaited(_attach(element, attempt)),
      ),
    );
  }
}
