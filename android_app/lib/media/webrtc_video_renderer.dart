import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

enum WebRtcVideoRenderPhase {
  idle,
  waitingForFrame,
  rendering,
  failed,
  disposed,
}

class WebRtcVideoRenderState {
  const WebRtcVideoRenderState({
    this.phase = WebRtcVideoRenderPhase.idle,
    this.trackId,
    this.width = 0,
    this.height = 0,
    this.error,
  });

  final WebRtcVideoRenderPhase phase;
  final String? trackId;
  final int width;
  final int height;
  final String? error;

  bool get hasFrame => phase == WebRtcVideoRenderPhase.rendering;
}

abstract interface class WebRtcVideoPlayback {
  Future<void> prepare();
  Future<void> attach(RTCTrackEvent event);
  Future<void> detach(MediaStreamTrack track);
  Future<void> reset();
  Future<void> dispose();
}

class FlutterWebRtcVideoRenderer implements WebRtcVideoPlayback {
  FlutterWebRtcVideoRenderer({RTCVideoRenderer? renderer})
      : renderer = renderer ?? RTCVideoRenderer();

  final RTCVideoRenderer renderer;
  final StreamController<WebRtcVideoRenderState> _states =
      StreamController<WebRtcVideoRenderState>.broadcast(sync: true);

  WebRtcVideoRenderState _state = const WebRtcVideoRenderState();
  MediaStream? _stream;
  MediaStreamTrack? _track;
  bool _ownsStream = false;
  bool _initialized = false;
  bool _disposed = false;

  WebRtcVideoRenderState get state => _state;
  Stream<WebRtcVideoRenderState> get states => _states.stream;
  bool get initialized => _initialized;

  @override
  Future<void> prepare() async {
    _ensureNotDisposed();
    if (_initialized) return;
    await renderer.initialize();
    renderer.onFirstFrameRendered = _handleFirstFrame;
    renderer.onResize = _handleResize;
    _initialized = true;
  }

  @override
  Future<void> attach(RTCTrackEvent event) async {
    _ensureNotDisposed();
    final track = event.track;
    if (track.kind != 'video') {
      throw ArgumentError('WebRTC renderer only accepts video tracks');
    }
    await prepare();
    if (_track?.id == track.id) return;

    await _clearCurrent(disableTrack: true);
    MediaStream? stream;
    var ownsStream = false;
    try {
      if (event.streams.isNotEmpty) {
        stream = event.streams.first;
      } else {
        stream = await createLocalMediaStream('smart-mpc-remote-video');
        ownsStream = true;
        await stream.addTrack(track);
      }
      track.enabled = true;
      _stream = stream;
      _track = track;
      _ownsStream = ownsStream;
      _emit(
        WebRtcVideoRenderState(
          phase: WebRtcVideoRenderPhase.waitingForFrame,
          trackId: track.id,
        ),
      );
      await renderer.setSrcObject(stream: stream, trackId: track.id);
    } catch (error) {
      if (ownsStream) await stream?.dispose();
      _stream = null;
      _track = null;
      _ownsStream = false;
      track.enabled = false;
      _emit(
        WebRtcVideoRenderState(
          phase: WebRtcVideoRenderPhase.failed,
          trackId: track.id,
          error: error.toString(),
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> detach(MediaStreamTrack track) async {
    if (_disposed) return;
    if (_track?.id != track.id) {
      track.enabled = false;
      return;
    }
    await _clearCurrent(disableTrack: true);
    _emit(const WebRtcVideoRenderState());
  }

  @override
  Future<void> reset() async {
    if (_disposed) return;
    await _clearCurrent(disableTrack: true);
    _emit(const WebRtcVideoRenderState());
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    Object? firstError;
    try {
      await _clearCurrent(disableTrack: true);
    } catch (error) {
      firstError = error;
    }
    renderer.onFirstFrameRendered = null;
    renderer.onResize = null;
    if (_initialized) {
      try {
        await renderer.dispose();
      } catch (error) {
        firstError ??= error;
      }
    }
    _initialized = false;
    _disposed = true;
    _emit(
      const WebRtcVideoRenderState(
        phase: WebRtcVideoRenderPhase.disposed,
      ),
    );
    await _states.close();
    if (firstError != null) throw firstError;
  }

  Future<void> _clearCurrent({required bool disableTrack}) async {
    final track = _track;
    final stream = _stream;
    final ownsStream = _ownsStream;
    _track = null;
    _stream = null;
    _ownsStream = false;
    Object? firstError;
    if (_initialized) {
      try {
        await renderer.setSrcObject(stream: null);
      } catch (error) {
        firstError = error;
      }
    }
    if (disableTrack && track != null) track.enabled = false;
    if (ownsStream) {
      try {
        await stream?.dispose();
      } catch (error) {
        firstError ??= error;
      }
    }
    if (firstError != null) throw firstError;
  }

  void _handleFirstFrame() {
    final track = _track;
    if (track == null || _disposed) return;
    _emit(
      WebRtcVideoRenderState(
        phase: WebRtcVideoRenderPhase.rendering,
        trackId: track.id,
        width: renderer.videoWidth,
        height: renderer.videoHeight,
      ),
    );
  }

  void _handleResize() {
    if (!_state.hasFrame || _track == null || _disposed) return;
    _emit(
      WebRtcVideoRenderState(
        phase: WebRtcVideoRenderPhase.rendering,
        trackId: _track!.id,
        width: renderer.videoWidth,
        height: renderer.videoHeight,
      ),
    );
  }

  void _emit(WebRtcVideoRenderState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('WebRTC video renderer is disposed');
  }
}
