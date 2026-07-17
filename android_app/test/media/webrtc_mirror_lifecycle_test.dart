import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_mpc/media/media_engine.dart';
import 'package:smart_mpc/media/media_state.dart';
import 'package:smart_mpc/media/webrtc_mirror_lifecycle.dart';

void main() {
  test('mirror follows tab visibility and Android foreground lifecycle',
      () async {
    final engine = FakeMediaEngine();
    final lifecycle = WebRtcMirrorLifecycle(engine: engine);

    await lifecycle.setVisible(true);
    expect(engine.startVideoCalls, 1);
    expect(engine.state.videoRequested, isTrue);

    await lifecycle.setAppLifecycleState(AppLifecycleState.paused);
    expect(engine.stopVideoCalls, 1);
    expect(engine.state.videoRequested, isFalse);

    await lifecycle.setAppLifecycleState(AppLifecycleState.resumed);
    expect(engine.startVideoCalls, 2);
    expect(engine.state.videoRequested, isTrue);

    await lifecycle.setVisible(false);
    expect(engine.stopVideoCalls, 2);
    expect(engine.state.videoRequested, isFalse);

    await lifecycle.dispose();
  });

  test('retry creates a fresh video session only while mirror is visible',
      () async {
    final engine = FakeMediaEngine();
    final lifecycle = WebRtcMirrorLifecycle(engine: engine);

    await lifecycle.setVisible(true);
    await lifecycle.retry();
    expect(engine.startVideoCalls, 2);
    expect(engine.stopVideoCalls, 1);

    await lifecycle.setVisible(false);
    await lifecycle.retry();
    expect(engine.startVideoCalls, 2);
    expect(engine.stopVideoCalls, 2);

    await lifecycle.dispose();
  });

  test('disposing a visible mirror releases video without disposing engine',
      () async {
    final engine = FakeMediaEngine();
    final lifecycle = WebRtcMirrorLifecycle(engine: engine);

    await lifecycle.setVisible(true);
    await lifecycle.dispose();

    expect(engine.stopVideoCalls, 1);
    expect(engine.disposeCalls, 0);
    expect(() => lifecycle.setVisible(true), throwsStateError);
  });
}

class FakeMediaEngine implements MediaEngine {
  MediaState _state = const MediaState();
  int startVideoCalls = 0;
  int stopVideoCalls = 0;
  int disposeCalls = 0;

  @override
  MediaState get state => _state;

  @override
  Stream<MediaState> get states => const Stream<MediaState>.empty();

  @override
  Future<void> initialize(TrustedPcMediaContext context) async {}

  @override
  Future<void> startAudio() async {
    _state = _state.copyWith(audioRequested: true);
  }

  @override
  Future<void> stopAudio() async {
    _state = _state.copyWith(audioRequested: false);
  }

  @override
  Future<void> startVideo() async {
    startVideoCalls += 1;
    _state = _state.copyWith(
      sessionPhase: MediaSessionPhase.connected,
      videoPhase: MediaTrackPhase.on,
      videoRequested: true,
    );
  }

  @override
  Future<void> stopVideo() async {
    stopVideoCalls += 1;
    _state = _state.copyWith(
      sessionPhase: MediaSessionPhase.idle,
      videoPhase: MediaTrackPhase.off,
      videoRequested: false,
    );
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }
}
