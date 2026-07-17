import 'package:flutter/services.dart';

class WebRtcMirrorSystemUi {
  bool _active = false;

  bool get active => _active;

  Future<void> enter() async {
    if (_active) return;
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _active = true;
  }

  Future<void> exit() async {
    if (!_active) return;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _active = false;
  }
}
