import 'dart:async';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

enum WebRtcMediaCommand { play, pause, stop }

class WebRtcMediaServiceBridge {
  WebRtcMediaServiceBridge._() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static final WebRtcMediaServiceBridge instance = WebRtcMediaServiceBridge._();
  static const MethodChannel _channel = MethodChannel('smart_mpc/webrtc_media');

  final StreamController<WebRtcMediaCommand> _commands =
      StreamController<WebRtcMediaCommand>.broadcast();

  Stream<WebRtcMediaCommand> get commands => _commands.stream;

  Future<bool> requestNotificationPermission() async {
    final current = await Permission.notification.status;
    if (current.isGranted) return true;
    return (await Permission.notification.request()).isGranted;
  }

  Future<bool> start({
    String title = 'PC Audio',
    bool playing = true,
    bool requestPermission = true,
  }) async {
    final notificationAllowed =
        !requestPermission || await requestNotificationPermission();
    await _channel.invokeMethod<void>('start', <String, Object>{
      'title': title,
      'playing': playing,
    });
    return notificationAllowed;
  }

  Future<void> update({
    String title = 'PC Audio',
    required bool playing,
  }) {
    return _channel.invokeMethod<void>('update', <String, Object>{
      'title': title,
      'playing': playing,
    });
  }

  Future<void> stop() => _channel.invokeMethod<void>('stop');

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'command') return;
    final command = switch (call.arguments) {
      'play' => WebRtcMediaCommand.play,
      'pause' => WebRtcMediaCommand.pause,
      'stop' => WebRtcMediaCommand.stop,
      _ => null,
    };
    if (command != null) _commands.add(command);
  }
}
