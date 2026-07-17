import 'media_state.dart';

class TrustedPcMediaContext {
  const TrustedPcMediaContext({
    required this.baseUri,
    required this.deviceId,
    required this.deviceToken,
  });

  final Uri baseUri;
  final String deviceId;
  final String deviceToken;
}

abstract interface class MediaEngine {
  MediaState get state;
  Stream<MediaState> get states;

  Future<void> initialize(TrustedPcMediaContext context);
  Future<void> startAudio();
  Future<void> stopAudio();
  Future<void> startVideo();
  Future<void> stopVideo();
  Future<void> dispose();
}
