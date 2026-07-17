import 'package:flutter_webrtc/flutter_webrtc.dart';

abstract interface class WebRtcAudioPlayback {
  Future<void> prepare();
  Future<void> attach(MediaStreamTrack track);
  Future<void> detach(MediaStreamTrack track);
  Future<void> reset();
}

class FlutterWebRtcAudioPlayback implements WebRtcAudioPlayback {
  @override
  Future<void> prepare() {
    return Helper.setAndroidAudioConfiguration(AndroidAudioConfiguration.media);
  }

  @override
  Future<void> attach(MediaStreamTrack track) async {
    track.enabled = true;
    await Helper.setVolume(1, track);
  }

  @override
  Future<void> detach(MediaStreamTrack track) async {
    track.enabled = false;
  }

  @override
  Future<void> reset() async {
    await Helper.clearAndroidCommunicationDevice();
  }
}
