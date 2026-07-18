import 'dart:async';

import 'package:flutter/widgets.dart';

import 'media_engine.dart';

class WebRtcMirrorLifecycle {
  WebRtcMirrorLifecycle({required MediaEngine engine}) : _engine = engine;

  final MediaEngine _engine;
  bool _visible = false;
  bool _foreground = true;
  bool _disposed = false;
  Future<void> _serial = Future<void>.value();

  bool get visible => _visible;
  bool get foreground => _foreground;
  bool get shouldStream => _visible && _foreground && !_disposed;

  Future<void> setVisible(bool visible) {
    _ensureNotDisposed();
    _visible = visible;
    return _enqueue(_reconcile);
  }

  Future<void> setAppLifecycleState(AppLifecycleState state) {
    _ensureNotDisposed();
    _foreground = state == AppLifecycleState.resumed;
    return _enqueue(_reconcile);
  }

  Future<void> retry() {
    _ensureNotDisposed();
    return _enqueue(() async {
      if (!shouldStream) return;
      if (_engine.state.videoRequested) await _engine.stopVideo();
      await _engine.startVideo();
    });
  }

  Future<void> dispose() {
    if (_disposed) return Future<void>.value();
    _visible = false;
    _foreground = false;
    return _enqueue(() async {
      if (_engine.state.videoRequested) await _engine.stopVideo();
      _disposed = true;
    });
  }

  Future<void> _reconcile() async {
    if (shouldStream && !_engine.state.videoRequested) {
      await _engine.startVideo();
      return;
    }
    if (!shouldStream && _engine.state.videoRequested) {
      await _engine.stopVideo();
    }
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _serial.then((_) => action());
    _serial = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('WebRTC mirror lifecycle is disposed');
  }
}
