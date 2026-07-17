import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'media_engine.dart';
import 'media_signaling_client.dart';
import 'media_state.dart';
import 'webrtc_peer.dart';

typedef MediaSignalingFactory = MediaSignalingTransport Function(
  TrustedPcMediaContext context,
);

class WebRtcMediaEngine implements MediaEngine {
  WebRtcMediaEngine({
    MediaSignalingFactory? signalingFactory,
    WebRtcPeerFactory? peerFactory,
  })  : _signalingFactory = signalingFactory ?? _defaultSignalingFactory,
        _peerFactory = peerFactory ?? createSmartMpcWebRtcPeer;

  final MediaSignalingFactory _signalingFactory;
  final WebRtcPeerFactory _peerFactory;
  final StreamController<MediaState> _states =
      StreamController<MediaState>.broadcast(sync: true);
  final StreamController<RTCTrackEvent> _remoteTracks =
      StreamController<RTCTrackEvent>.broadcast(sync: true);

  MediaSignalingTransport? _signaling;
  WebRtcPeer? _peer;
  String? _sessionId;
  bool _sessionAudio = false;
  bool _sessionVideo = false;
  bool _audioRequested = false;
  bool _videoRequested = false;
  bool _capabilitiesChecked = false;
  bool _remoteDescriptionSet = false;
  bool _disposed = false;
  int _serverSequence = 0;
  int _generation = 0;
  Future<void> _serial = Future<void>.value();
  final List<WebRtcIceCandidate> _pendingRemoteCandidates = [];
  MediaState _state = const MediaState();

  @override
  MediaState get state => _state;

  @override
  Stream<MediaState> get states => _states.stream;

  Stream<RTCTrackEvent> get remoteTracks => _remoteTracks.stream;

  @override
  Future<void> initialize(TrustedPcMediaContext context) {
    return _enqueue(() async {
      _ensureNotDisposed();
      if (_signaling != null) {
        throw StateError('WebRTC media engine is already initialized');
      }
      if (context.deviceId.trim().isEmpty ||
          context.deviceToken.trim().isEmpty) {
        throw ArgumentError('Trusted PC media context is incomplete');
      }
      _signaling = _signalingFactory(context);
      _emit(const MediaState());
    });
  }

  @override
  Future<void> startAudio() {
    return _enqueue(() async {
      _ensureReady();
      _audioRequested = true;
      await _reconcile();
    });
  }

  @override
  Future<void> stopAudio() {
    return _enqueue(() async {
      _ensureReady();
      _audioRequested = false;
      await _reconcile();
    });
  }

  @override
  Future<void> startVideo() {
    return _enqueue(() async {
      _ensureReady();
      _videoRequested = true;
      await _reconcile();
    });
  }

  @override
  Future<void> stopVideo() {
    return _enqueue(() async {
      _ensureReady();
      _videoRequested = false;
      await _reconcile();
    });
  }

  @override
  Future<void> dispose() {
    return _enqueue(() async {
      if (_disposed) return;
      _audioRequested = false;
      _videoRequested = false;
      await _stopActive(emitState: true);
      _signaling?.dispose();
      _signaling = null;
      _disposed = true;
      await _remoteTracks.close();
      await _states.close();
    });
  }

  Future<void> _reconcile() async {
    final alreadyMatches = _peer != null &&
        _sessionAudio == _audioRequested &&
        _sessionVideo == _videoRequested;
    if (alreadyMatches) return;

    if (_peer != null || _sessionId != null) {
      await _stopActive(emitState: true);
    }
    if (!_audioRequested && !_videoRequested) {
      _emitIdle();
      return;
    }
    await _startActive();
  }

  Future<void> _startActive() async {
    final signaling = _signaling!;
    final audio = _audioRequested;
    final video = _videoRequested;
    _emit(
      MediaState(
        sessionPhase: MediaSessionPhase.starting,
        audioPhase: audio ? MediaTrackPhase.starting : MediaTrackPhase.off,
        videoPhase: video ? MediaTrackPhase.starting : MediaTrackPhase.off,
        audioRequested: audio,
        videoRequested: video,
      ),
    );

    try {
      await _ensureWebRtcAvailable(signaling);
      final response =
          await signaling.createSession(audio: audio, video: video);
      final session = _requiredMap(response, 'session');
      final sessionId = _requiredText(session, 'session_id');
      final generation = ++_generation;

      _sessionId = sessionId;
      _sessionAudio = audio;
      _sessionVideo = video;
      _serverSequence = 0;
      _remoteDescriptionSet = false;
      _pendingRemoteCandidates.clear();
      final peer = await _peerFactory();
      _peer = peer;
      _bindPeer(peer, sessionId, generation);

      if (audio) await peer.addReceiveOnly(WebRtcMediaKind.audio);
      if (video) await peer.addReceiveOnly(WebRtcMediaKind.video);

      _emit(
        MediaState(
          sessionPhase: MediaSessionPhase.negotiating,
          audioPhase: audio ? MediaTrackPhase.starting : MediaTrackPhase.off,
          videoPhase: video ? MediaTrackPhase.starting : MediaTrackPhase.off,
          audioRequested: audio,
          videoRequested: video,
          sessionId: sessionId,
        ),
      );

      final offer = await peer.createOffer();
      await signaling.sendSignal(
        sessionId,
        <String, dynamic>{'kind': 'offer', 'sdp': offer},
      );
      unawaited(_pollSignals(sessionId, generation));
    } catch (error) {
      await _stopActive(emitState: false);
      _emitFailure(error);
      rethrow;
    }
  }

  void _bindPeer(WebRtcPeer peer, String sessionId, int generation) {
    peer.onLocalCandidate = (candidate) {
      if (!_isCurrent(sessionId, generation)) return;
      final signal = candidate == null
          ? <String, dynamic>{'kind': 'ice-complete'}
          : <String, dynamic>{
              'kind': 'ice-candidate',
              'candidate': candidate.candidate,
              'sdp_mid': candidate.sdpMid,
              'sdp_mline_index': candidate.sdpMLineIndex,
            };
      unawaited(_sendLocalSignal(sessionId, generation, signal));
    };
    peer.onState = (peerState) => _handlePeerState(
          sessionId,
          generation,
          peerState,
        );
    peer.onTrack = (event) {
      if (_isCurrent(sessionId, generation) && !_remoteTracks.isClosed) {
        _remoteTracks.add(event);
      }
    };
  }

  Future<void> _sendLocalSignal(
    String sessionId,
    int generation,
    Map<String, dynamic> signal,
  ) async {
    try {
      await _signaling?.sendSignal(sessionId, signal);
    } catch (error) {
      if (_isCurrent(sessionId, generation)) {
        _scheduleFailure(sessionId, generation, error);
      }
    }
  }

  Future<void> _pollSignals(String sessionId, int generation) async {
    while (_isCurrent(sessionId, generation)) {
      try {
        final response = await _signaling!.pollSignals(
          sessionId,
          after: _serverSequence,
        );
        if (!_isCurrent(sessionId, generation)) return;
        final signals = response['signals'];
        if (signals is! List) {
          throw const FormatException('PC returned invalid media signals');
        }
        for (final value in signals) {
          if (value is! Map) {
            throw const FormatException('PC returned an invalid media signal');
          }
          final signal = Map<String, dynamic>.from(value);
          final sequence = signal['sequence'];
          if (sequence is int && sequence > _serverSequence) {
            _serverSequence = sequence;
          }
          await _applyServerSignal(signal);
        }
        if (response['stopped'] == true) {
          throw StateError('PC stopped the media session');
        }
      } catch (error) {
        if (_isCurrent(sessionId, generation)) {
          _scheduleFailure(sessionId, generation, error);
        }
        return;
      }
    }
  }

  Future<void> _applyServerSignal(Map<String, dynamic> signal) async {
    final kind = signal['kind']?.toString();
    if (kind == 'answer') {
      final sdp = _requiredText(signal, 'sdp');
      await _peer!.setRemoteAnswer(sdp);
      _remoteDescriptionSet = true;
      for (final candidate in _pendingRemoteCandidates) {
        await _peer!.addRemoteCandidate(candidate);
      }
      _pendingRemoteCandidates.clear();
      return;
    }
    if (kind == 'ice-candidate') {
      final candidate = WebRtcIceCandidate(
        candidate: _requiredText(signal, 'candidate'),
        sdpMid: signal['sdp_mid']?.toString(),
        sdpMLineIndex: signal['sdp_mline_index'] is int
            ? signal['sdp_mline_index'] as int
            : null,
      );
      if (_remoteDescriptionSet) {
        await _peer!.addRemoteCandidate(candidate);
      } else {
        _pendingRemoteCandidates.add(candidate);
      }
      return;
    }
    if (kind == 'ice-complete') return;
    if (kind == 'error') {
      throw StateError(
          signal['message']?.toString() ?? 'PC media worker failed');
    }
    throw FormatException('Unsupported PC media signal: $kind');
  }

  void _handlePeerState(
    String sessionId,
    int generation,
    WebRtcPeerState peerState,
  ) {
    if (!_isCurrent(sessionId, generation)) return;
    if (peerState == WebRtcPeerState.connected) {
      _emit(
        _state.copyWith(
          sessionPhase: MediaSessionPhase.connected,
          audioPhase: _sessionAudio ? MediaTrackPhase.on : MediaTrackPhase.off,
          videoPhase: _sessionVideo ? MediaTrackPhase.on : MediaTrackPhase.off,
          clearError: true,
        ),
      );
      return;
    }
    if (peerState == WebRtcPeerState.disconnected ||
        peerState == WebRtcPeerState.failed ||
        peerState == WebRtcPeerState.closed) {
      _scheduleFailure(
        sessionId,
        generation,
        StateError('WebRTC peer ${peerState.name}'),
      );
    }
  }

  void _scheduleFailure(String sessionId, int generation, Object error) {
    unawaited(
      _enqueue(() async {
        if (!_isCurrent(sessionId, generation)) return;
        await _stopActive(emitState: false);
        _emitFailure(error);
      }),
    );
  }

  Future<void> _stopActive({required bool emitState}) async {
    final peer = _peer;
    final sessionId = _sessionId;
    if (peer == null && sessionId == null) {
      if (emitState) _emitIdle();
      return;
    }

    ++_generation;
    if (emitState) {
      _emit(
        _state.copyWith(
          sessionPhase: MediaSessionPhase.stopping,
          audioPhase:
              _sessionAudio ? MediaTrackPhase.stopping : MediaTrackPhase.off,
          videoPhase:
              _sessionVideo ? MediaTrackPhase.stopping : MediaTrackPhase.off,
        ),
      );
    }
    _peer = null;
    _sessionId = null;
    _sessionAudio = false;
    _sessionVideo = false;
    _serverSequence = 0;
    _remoteDescriptionSet = false;
    _pendingRemoteCandidates.clear();

    peer?.onLocalCandidate = null;
    peer?.onState = null;
    peer?.onTrack = null;
    Object? firstError;
    try {
      await peer?.close();
    } catch (error) {
      firstError = error;
    }
    if (sessionId != null) {
      try {
        await _signaling?.stopSession(sessionId);
      } catch (error) {
        firstError ??= error;
      }
    }
    if (emitState) _emitIdle();
    if (firstError != null) throw firstError;
  }

  Future<void> _ensureWebRtcAvailable(MediaSignalingTransport signaling) async {
    if (_capabilitiesChecked) return;
    final response = await signaling.capabilities();
    final capabilities = _requiredMap(response, 'capabilities');
    final engines = _requiredMap(capabilities, 'engines');
    final webrtc = _requiredMap(engines, 'webrtc');
    if (webrtc['signaling_available'] != true ||
        webrtc['media_available'] != true) {
      throw StateError('PC WebRTC media engine is unavailable');
    }
    _capabilitiesChecked = true;
  }

  void _emitIdle() {
    _emit(
      MediaState(
        audioRequested: _audioRequested,
        videoRequested: _videoRequested,
      ),
    );
  }

  void _emitFailure(Object error) {
    _emit(
      MediaState(
        sessionPhase: MediaSessionPhase.failed,
        audioPhase:
            _audioRequested ? MediaTrackPhase.failed : MediaTrackPhase.off,
        videoPhase:
            _videoRequested ? MediaTrackPhase.failed : MediaTrackPhase.off,
        audioRequested: _audioRequested,
        videoRequested: _videoRequested,
        error: error.toString(),
      ),
    );
  }

  void _emit(MediaState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  bool _isCurrent(String sessionId, int generation) {
    return !_disposed && _sessionId == sessionId && _generation == generation;
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _serial.then((_) => action());
    _serial = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  void _ensureReady() {
    _ensureNotDisposed();
    if (_signaling == null) {
      throw StateError('WebRTC media engine is not initialized');
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('WebRTC media engine is disposed');
  }

  static MediaSignalingTransport _defaultSignalingFactory(
    TrustedPcMediaContext context,
  ) {
    return MediaSignalingClient(
      baseUri: context.baseUri,
      deviceId: context.deviceId,
      deviceToken: context.deviceToken,
    );
  }
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> source, String key) {
  final value = source[key];
  if (value is! Map) throw FormatException('Missing signaling field: $key');
  return Map<String, dynamic>.from(value);
}

String _requiredText(Map<String, dynamic> source, String key) {
  final value = source[key]?.toString().trim() ?? '';
  if (value.isEmpty) throw FormatException('Missing signaling field: $key');
  return value;
}
