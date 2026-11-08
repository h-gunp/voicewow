import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/features/prosody/presentation/prosody_web_frame_contract.dart';

void main() {
  test('bundled frame stays at the host origin and deployment base path', () {
    final root = Uri.parse('https://voicemate.example/?feature=prosody');
    expect(
      embeddedProsodyUri(root).toString(),
      'https://voicemate.example/prosody/index.html?embedded=1',
    );
    final nested = Uri.parse(
      'http://localhost:8765/team/app/index.html#record',
    );
    final source = embeddedProsodyUri(nested);
    expect(source.origin, nested.origin);
    expect(source.path, '/team/app/prosody/index.html');
    expect(source.queryParameters, {'embedded': '1'});
    expect(source.fragment, isEmpty);
    expect(embeddedProsodyUri(nested, textScale: 1.875).queryParameters, {
      'embedded': '1',
      'textScale': '1.875',
    });
    expect(embeddedProsodyUri(nested, textScale: double.nan).queryParameters, {
      'embedded': '1',
    });
  });

  test(
    'only the current same-origin frame can announce readiness or failure',
    () {
      for (final type in [prosodyReadyMessage, prosodyErrorMessage]) {
        bool accept({
          String origin = 'https://voicemate.example',
          bool fromFrame = true,
          Object? data,
        }) => acceptsProsodyMessage(
          origin: origin,
          expectedOrigin: 'https://voicemate.example',
          fromFrame: fromFrame,
          data: data ?? {'type': type},
          type: type,
        );
        expect(accept(), isTrue);
        expect(accept(origin: 'https://elsewhere.example'), isFalse);
        expect(accept(fromFrame: false), isFalse);
        expect(accept(data: type), isFalse);
        expect(accept(data: {'type': prosodyExitMessage}), isFalse);
      }
    },
  );

  test('only the actual same-origin frame can request an exit', () {
    bool accept({
      String origin = 'https://voicemate.example',
      bool fromFrame = true,
      Object? data = const {'type': prosodyExitMessage},
    }) => acceptsProsodyExit(
      origin: origin,
      expectedOrigin: 'https://voicemate.example',
      fromFrame: fromFrame,
      data: data,
    );
    expect(accept(), isTrue);
    expect(accept(origin: 'https://elsewhere.example'), isFalse);
    expect(accept(origin: 'http://voicemate.example'), isFalse);
    expect(accept(origin: 'https://voicemate.example:8443'), isFalse);
    expect(accept(fromFrame: false), isFalse);
    expect(accept(data: null), isFalse);
    expect(accept(data: prosodyExitMessage), isFalse);
    expect(accept(data: {'type': prosodyCleanupMessage}), isFalse);
  });

  test('opening a frame starts no audio and leaving stops before removal', () {
    final port = _FakeFramePort();
    final lifecycle = ProsodyFrameLifecycle(port);
    expect(port.events, isEmpty);
    lifecycle.dispose();
    expect(port.events, ['message', 'synchronous-stop', 'remove']);
    expect(port.audioActive, isFalse);
    expect(port.removed, isTrue);
    lifecycle.dispose();
    lifecycle.stopAudio();
    expect(port.events, hasLength(3));
  });

  test('background cleanup stops audio without removing a visible frame', () {
    final port = _FakeFramePort();
    final lifecycle = ProsodyFrameLifecycle(port);
    lifecycle.stopAudio();
    expect(port.audioActive, isFalse);
    expect(port.removed, isFalse);
    lifecycle.dispose();
    expect(port.events.last, 'remove');
  });

  test(
    'an unload message failure still releases audio and removes the frame',
    () {
      final port = _FakeFramePort(failMessage: true);
      ProsodyFrameLifecycle(port).dispose();
      expect(port.events, ['message', 'synchronous-stop', 'remove']);
      expect(port.audioActive, isFalse);
      expect(port.removed, isTrue);
    },
  );

  test(
    'a missing same-origin cleanup hook still removes the browsing context',
    () {
      final port = _FakeFramePort(failHook: true);
      ProsodyFrameLifecycle(port).dispose();
      expect(port.events, ['message', 'synchronous-stop', 'remove']);
      expect(port.removed, isTrue);
    },
  );
}

class _FakeFramePort implements ProsodyFramePort {
  _FakeFramePort({this.failMessage = false, this.failHook = false});
  final bool failMessage, failHook;
  final events = <String>[];
  bool audioActive = true, removed = false;

  @override
  void postCleanup() {
    events.add('message');
    if (failMessage) throw StateError('document already unloaded');
  }

  @override
  void stopSameOriginAudio() {
    events.add('synchronous-stop');
    if (failHook) throw StateError('hook not installed yet');
    audioActive = false;
  }

  @override
  void remove() {
    events.add('remove');
    removed = true;
  }
}
