import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'media_engine.dart';
import 'media_signaling_client.dart';
import 'media_state.dart';
import 'webrtc_audio_playback.dart';
import 'webrtc_peer.dart';
import 'webrtc_video_renderer.dart';

typedef MediaSignalingFactory = MediaSignalingTransport Function(
  TrustedPcMediaContext context,
);

class WebRtcMediaEngine implements MediaEngine {
  WebRtcMediaEngine({
    MediaSignalingFactory? signalingFactory,
    WebRtcPeerFactory? peerFactory,
    WebRtcAudioPlayback? audioPlayback,
    WebRtcVideoPlayback? videoPlayback,
    List<Duration>? reconnectDelays,
    this.disconnectGrace = const Duration(milliseconds: 1200),
    this.connectionTimeout = const Duration(seconds: 12),
  })  : _signalingFactory = signalingFactory ?? _defaultSignalingFactory,
        _peerFactory = peerFactory ?? createSmartMpcWebRtcPeer,
        _audioPlayback = audioPlayback ?? FlutterWebRtcAudioPlayback(),
        _videoPlayback = videoPlayback ?? FlutterWebRtcVideoRenderer(),
        _reconnectDelays = reconnectDelays ??
            const [
              Duration(milliseconds: 250),
              Duration(milliseconds: 750),
              Duration(milliseconds: 1500),
            ];

  final MediaSignalingFactory _signalingFactory;
  final WebRtcPeerFactory _peerFactory;
  final WebRtcAudioPlayback _audioPlayback;
  final WebRtcVideoPlayback _videoPlayback;
  final List<Duration> _reconnectDelays;
  final Duration disconnectGrace;
  final Duration connectionTimeout;
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
  bool _peerConnected = false;
  bool _audioTrackReady = false;
  bool _videoTrackReady = false;
  int _serverSequence = 0;
  int _generation = 0;
  int _reconnectTicket = 0;
  int _reconnectAttempt = 0;
  WebRtcPeerState _lastPeerState = WebRtcPeerState.fresh;
  MediaStreamTrack? _remoteAudioTrack;
  MediaStreamTrack? _remoteVideoTrack;
  Timer? _connectionTimer;
  Timer? _disconnectTimer;
  Timer? _reconnectTimer;
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
      _cancelReconnect(resetAttempt: true);
      _audioRequested = true;
      await _reconcile();
    });
  }

  @override
  Future<void> stopAudio() {
    return _enqueue(() async {
      _ensureReady();
      _cancelReconnect(resetAttempt: true);
      _audioRequested = false;
      await _reconcile();
    });
  }

  @override
  Future<void> startVideo() {
    return _enqueue(() async {
      _ensureReady();
      _cancelReconnect(resetAttempt: true);
      _videoRequested = true;
      await _reconcile();
    });
  }

  @override
  Future<void> stopVideo() {
    return _enqueue(() async {
      _ensureReady();
      _cancelReconnect(resetAttempt: true);
      _videoRequested = false;
      await _reconcile();
    });
  }

  @override
  Future<void> dispose() {
    return _enqueue(() async {
      if (_disposed) return;
      _cancelReconnect(resetAttempt: true);
      _audioRequested = false;
      _videoRequested = false;
      Object? firstError;
      try {
        await _stopActive(emitState: true);
      } catch (error) {
        firstError = error;
      }
      try {
        await _videoPlayback.dispose();
      } catch (error) {
        firstError ??= error;
      }
      try {
        _signaling?.dispose();
      } catch (error) {
        firstError ??= error;
      }
      _signaling = null;
      _disposed = true;
      await _remoteTracks.close();
      await _states.close();
      if (firstError != null) throw firstError;
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
      _peerConnected = false;
      _audioTrackReady = false;
      _videoTrackReady = false;
      _lastPeerState = WebRtcPeerState.fresh;
      _pendingRemoteCandidates.clear();
      if (audio) await _audioPlayback.prepare();
      if (video) await _videoPlayback.prepare();
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
      _scheduleConnectionTimeout(sessionId, generation);
    } catch (error) {
      Object failure = error;
      try {
        await _stopActive(emitState: false);
      } catch (cleanupError) {
        failure = StateError('$error; cleanup failed: $cleanupError');
      }
      _emitFailure(failure);
      throw failure;
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
        unawaited(_handleRemoteTrack(sessionId, generation, event));
      }
    };
  }

  Future<void> _handleRemoteTrack(
    String sessionId,
    int generation,
    RTCTrackEvent event,
  ) async {
    if (!_isCurrent(sessionId, generation)) return;
    if (event.track.kind == 'audio' && _sessionAudio) {
      try {
        await _audioPlayback.attach(event.track);
        if (!_isCurrent(sessionId, generation)) {
          await _audioPlayback.detach(event.track);
          return;
        }
        final previous = _remoteAudioTrack;
        _remoteAudioTrack = event.track;
        _audioTrackReady = true;
        if (previous != null && previous.id != event.track.id) {
          await _audioPlayback.detach(previous);
        }
        _publishConnectedState();
      } catch (error) {
        if (_isCurrent(sessionId, generation)) {
          _scheduleFailure(sessionId, generation, error);
        }
      }
      return;
    }
    if (event.track.kind == 'video' && _sessionVideo) {
      try {
        await _videoPlayback.attach(event);
        if (!_isCurrent(sessionId, generation)) {
          await _videoPlayback.detach(event.track);
          return;
        }
        final previous = _remoteVideoTrack;
        _remoteVideoTrack = event.track;
        _videoTrackReady = true;
        if (previous != null && previous.id != event.track.id) {
          await _videoPlayback.detach(previous);
        }
        _publishConnectedState();
      } catch (error) {
        if (_isCurrent(sessionId, generation)) {
          _scheduleFailure(sessionId, generation, error);
        }
      }
    }
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
      final sdp = _requiredSdp(signal);
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
    _lastPeerState = peerState;
    if (peerState == WebRtcPeerState.connected) {
      _peerConnected = true;
      _connectionTimer?.cancel();
      _connectionTimer = null;
      _disconnectTimer?.cancel();
      _disconnectTimer = null;
      _cancelReconnect(resetAttempt: true);
      _publishConnectedState();
      return;
    }
    if (peerState == WebRtcPeerState.disconnected) {
      _peerConnected = false;
      _disconnectTimer?.cancel();
      _disconnectTimer = Timer(disconnectGrace, () {
        if (_isCurrent(sessionId, generation) &&
            _lastPeerState == WebRtcPeerState.disconnected) {
          _scheduleFailure(
            sessionId,
            generation,
            StateError('WebRTC peer remained disconnected'),
          );
        }
      });
      return;
    }
    if (peerState == WebRtcPeerState.failed ||
        peerState == WebRtcPeerState.closed) {
      _peerConnected = false;
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
        Object failure = error;
        try {
          await _stopActive(emitState: false);
        } catch (cleanupError) {
          failure = StateError('$error; cleanup failed: $cleanupError');
        }
        _emitFailure(failure);
        _scheduleReconnect();
      }),
    );
  }

  void _scheduleConnectionTimeout(String sessionId, int generation) {
    _connectionTimer?.cancel();
    _connectionTimer = Timer(connectionTimeout, () {
      if (_isCurrent(sessionId, generation) && !_peerConnected) {
        _scheduleFailure(
          sessionId,
          generation,
          StateError('WebRTC connection timed out'),
        );
      }
    });
  }

  void _scheduleReconnect() {
    if (_disposed || !_audioRequested && !_videoRequested) return;
    if (_reconnectAttempt >= _reconnectDelays.length) return;
    final delay = _reconnectDelays[_reconnectAttempt++];
    final ticket = ++_reconnectTicket;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (_disposed ||
          ticket != _reconnectTicket ||
          !_audioRequested && !_videoRequested) {
        return;
      }
      unawaited(
        _enqueue(() async {
          if (_disposed ||
              ticket != _reconnectTicket ||
              _peer != null ||
              !_audioRequested && !_videoRequested) {
            return;
          }
          try {
            await _startActive();
          } catch (_) {
            _scheduleReconnect();
          }
        }),
      );
    });
  }

  void _cancelReconnect({required bool resetAttempt}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectTicket += 1;
    if (resetAttempt) _reconnectAttempt = 0;
  }

  void _publishConnectedState() {
    if (!_peerConnected) return;
    _emit(
      _state.copyWith(
        sessionPhase: MediaSessionPhase.connected,
        audioPhase: _sessionAudio
            ? (_audioTrackReady ? MediaTrackPhase.on : MediaTrackPhase.starting)
            : MediaTrackPhase.off,
        videoPhase: _sessionVideo
            ? (_videoTrackReady ? MediaTrackPhase.on : MediaTrackPhase.starting)
            : MediaTrackPhase.off,
        clearError: true,
      ),
    );
  }

  Future<void> _stopActive({required bool emitState}) async {
    final peer = _peer;
    final sessionId = _sessionId;
    final remoteAudioTrack = _remoteAudioTrack;
    final remoteVideoTrack = _remoteVideoTrack;
    final hadAudio = _sessionAudio;
    final hadVideo = _sessionVideo;
    if (peer == null && sessionId == null) {
      if (emitState) _emitIdle();
      return;
    }

    ++_generation;
    _cancelReconnect(resetAttempt: false);
    _connectionTimer?.cancel();
    _connectionTimer = null;
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
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
    _peerConnected = false;
    _audioTrackReady = false;
    _videoTrackReady = false;
    _lastPeerState = WebRtcPeerState.fresh;
    _remoteAudioTrack = null;
    _remoteVideoTrack = null;
    _serverSequence = 0;
    _remoteDescriptionSet = false;
    _pendingRemoteCandidates.clear();

    peer?.onLocalCandidate = null;
    peer?.onState = null;
    peer?.onTrack = null;
    Object? firstError;
    if (remoteAudioTrack != null) {
      try {
        await _audioPlayback.detach(remoteAudioTrack);
      } catch (error) {
        firstError = error;
      }
    }
    if (hadAudio) {
      try {
        await _audioPlayback.reset();
      } catch (error) {
        firstError ??= error;
      }
    }
    if (remoteVideoTrack != null) {
      try {
        await _videoPlayback.detach(remoteVideoTrack);
      } catch (error) {
        firstError ??= error;
      }
    }
    if (hadVideo) {
      try {
        await _videoPlayback.reset();
      } catch (error) {
        firstError ??= error;
      }
    }
    try {
      await peer?.close();
    } catch (error) {
      firstError ??= error;
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

String _requiredSdp(Map<String, dynamic> source) {
  final value = source['sdp']?.toString() ?? '';
  if (value.trim().isEmpty) {
    throw const FormatException('Missing signaling field: sdp');
  }
  final normalized = value.replaceAll(RegExp(r'\r\n|\r|\n'), '\r\n');
  return normalized.endsWith('\r\n') ? normalized : '$normalized\r\n';
}
