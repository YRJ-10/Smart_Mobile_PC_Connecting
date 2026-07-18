enum MediaSessionPhase {
  idle,
  starting,
  negotiating,
  connected,
  stopping,
  failed,
}

enum MediaTrackPhase {
  off,
  starting,
  on,
  stopping,
  failed,
}

class MediaState {
  const MediaState({
    this.sessionPhase = MediaSessionPhase.idle,
    this.audioPhase = MediaTrackPhase.off,
    this.videoPhase = MediaTrackPhase.off,
    this.audioRequested = false,
    this.videoRequested = false,
    this.sessionId,
    this.error,
  });

  final MediaSessionPhase sessionPhase;
  final MediaTrackPhase audioPhase;
  final MediaTrackPhase videoPhase;
  final bool audioRequested;
  final bool videoRequested;
  final String? sessionId;
  final String? error;

  bool get hasRequestedTracks => audioRequested || videoRequested;
  bool get isActive => sessionPhase != MediaSessionPhase.idle;

  MediaState copyWith({
    MediaSessionPhase? sessionPhase,
    MediaTrackPhase? audioPhase,
    MediaTrackPhase? videoPhase,
    bool? audioRequested,
    bool? videoRequested,
    String? sessionId,
    bool clearSessionId = false,
    String? error,
    bool clearError = false,
  }) {
    return MediaState(
      sessionPhase: sessionPhase ?? this.sessionPhase,
      audioPhase: audioPhase ?? this.audioPhase,
      videoPhase: videoPhase ?? this.videoPhase,
      audioRequested: audioRequested ?? this.audioRequested,
      videoRequested: videoRequested ?? this.videoRequested,
      sessionId: clearSessionId ? null : sessionId ?? this.sessionId,
      error: clearError ? null : error ?? this.error,
    );
  }
}
