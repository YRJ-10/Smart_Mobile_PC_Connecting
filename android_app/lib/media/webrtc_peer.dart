import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

enum WebRtcMediaKind { audio, video }

enum WebRtcPeerState {
  fresh,
  connecting,
  connected,
  disconnected,
  failed,
  closed
}

class WebRtcIceCandidate {
  const WebRtcIceCandidate({
    required this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
  });

  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;
}

abstract interface class WebRtcPeer {
  set onLocalCandidate(void Function(WebRtcIceCandidate? candidate)? callback);
  set onState(void Function(WebRtcPeerState state)? callback);
  set onTrack(void Function(RTCTrackEvent event)? callback);

  Future<void> addReceiveOnly(WebRtcMediaKind kind);
  Future<String> createOffer();
  Future<void> setRemoteAnswer(String sdp);
  Future<void> addRemoteCandidate(WebRtcIceCandidate candidate);
  Future<void> close();
}

typedef WebRtcPeerFactory = Future<WebRtcPeer> Function();

Future<WebRtcPeer> createSmartMpcWebRtcPeer() async {
  const configuration = <String, dynamic>{
    'iceServers': <Map<String, dynamic>>[],
    'sdpSemantics': 'unified-plan',
  };
  final peer = await createPeerConnection(configuration);
  return FlutterWebRtcPeer(peer);
}

class FlutterWebRtcPeer implements WebRtcPeer {
  FlutterWebRtcPeer(this._peer) {
    _peer.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        final completer = _iceGatheringCompleter;
        if (completer != null && !completer.isCompleted) completer.complete();
      }
    };
    _peer.onConnectionState = (state) {
      _onState?.call(_mapState(state));
    };
    _peer.onTrack = (event) => _onTrack?.call(event);
  }

  final RTCPeerConnection _peer;
  void Function(WebRtcPeerState state)? _onState;
  void Function(RTCTrackEvent event)? _onTrack;
  Completer<void>? _iceGatheringCompleter;
  bool _receiveAudio = false;
  bool _receiveVideo = false;

  @override
  set onLocalCandidate(
    void Function(WebRtcIceCandidate? candidate)? callback,
  ) {}

  @override
  set onState(void Function(WebRtcPeerState state)? callback) {
    _onState = callback;
  }

  @override
  set onTrack(void Function(RTCTrackEvent event)? callback) {
    _onTrack = callback;
  }

  @override
  Future<void> addReceiveOnly(WebRtcMediaKind kind) async {
    final isAudio = kind == WebRtcMediaKind.audio;
    if (isAudio) {
      _receiveAudio = true;
    } else {
      _receiveVideo = true;
    }
    await _peer.addTransceiver(
      kind: isAudio
          ? RTCRtpMediaType.RTCRtpMediaTypeAudio
          : RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(
        direction: TransceiverDirection.RecvOnly,
      ),
    );
  }

  @override
  Future<String> createOffer() async {
    final offer = await _peer.createOffer(
      <String, dynamic>{
        'mandatory': <String, dynamic>{
          'OfferToReceiveAudio': _receiveAudio,
          'OfferToReceiveVideo': _receiveVideo,
        },
        'optional': <dynamic>[],
      },
    );
    final gathering = Completer<void>();
    _iceGatheringCompleter = gathering;
    await _peer.setLocalDescription(offer);
    final state = await _peer.getIceGatheringState();
    if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
        !gathering.isCompleted) {
      gathering.complete();
    }
    await gathering.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {},
    );
    if (identical(_iceGatheringCompleter, gathering)) {
      _iceGatheringCompleter = null;
    }
    final description = await _peer.getLocalDescription();
    final sdp = description?.sdp;
    if (sdp == null || sdp.isEmpty) {
      throw StateError('WebRTC did not create a local offer');
    }
    return sdp;
  }

  @override
  Future<void> setRemoteAnswer(String sdp) {
    return _peer.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
  }

  @override
  Future<void> addRemoteCandidate(WebRtcIceCandidate candidate) {
    return _peer.addCandidate(
      RTCIceCandidate(
        candidate.candidate,
        candidate.sdpMid,
        candidate.sdpMLineIndex,
      ),
    );
  }

  @override
  Future<void> close() async {
    _peer.onIceCandidate = null;
    _peer.onIceGatheringState = null;
    _peer.onConnectionState = null;
    _peer.onTrack = null;
    await _peer.close();
  }

  static WebRtcPeerState _mapState(RTCPeerConnectionState state) {
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
        return WebRtcPeerState.fresh;
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        return WebRtcPeerState.connecting;
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        return WebRtcPeerState.connected;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        return WebRtcPeerState.disconnected;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        return WebRtcPeerState.failed;
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        return WebRtcPeerState.closed;
    }
  }
}
