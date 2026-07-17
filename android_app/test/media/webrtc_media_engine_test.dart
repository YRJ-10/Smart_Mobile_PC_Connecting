import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:smart_mpc/media/media_engine.dart';
import 'package:smart_mpc/media/media_signaling_client.dart';
import 'package:smart_mpc/media/media_state.dart';
import 'package:smart_mpc/media/webrtc_media_engine.dart';
import 'package:smart_mpc/media/webrtc_peer.dart';

void main() {
  test('peer lifecycle follows requested tracks and cleans every old session',
      () async {
    final signaling = FakeSignaling();
    final peers = <FakePeer>[];
    final engine = WebRtcMediaEngine(
      signalingFactory: (_) => signaling,
      peerFactory: () async {
        final peer = FakePeer(peers.length + 1);
        peers.add(peer);
        return peer;
      },
    );

    await engine.initialize(testContext);
    expect(engine.state.sessionPhase, MediaSessionPhase.idle);

    await engine.startAudio();
    expect(signaling.created, [(audio: true, video: false)]);
    expect(peers.single.receiveOnly, [WebRtcMediaKind.audio]);
    expect(signaling.sent.single.signal['kind'], 'offer');
    expect(engine.state.sessionPhase, MediaSessionPhase.negotiating);

    signaling.deliver('session-1', [
      {
        'sequence': 1,
        'kind': 'ice-candidate',
        'candidate': 'pc-candidate',
        'sdp_mid': '0',
        'sdp_mline_index': 0,
      },
      {'sequence': 2, 'kind': 'answer', 'sdp': 'pc-answer'},
    ]);
    await eventually(() => peers.first.remoteAnswer == 'pc-answer');
    expect(peers.first.remoteCandidates.single.candidate, 'pc-candidate');

    peers.first.emitState(WebRtcPeerState.connected);
    expect(engine.state.sessionPhase, MediaSessionPhase.connected);
    expect(engine.state.audioPhase, MediaTrackPhase.on);

    peers.first.emitCandidate(
      const WebRtcIceCandidate(
        candidate: 'phone-candidate',
        sdpMid: '0',
        sdpMLineIndex: 0,
      ),
    );
    await eventually(
      () => signaling.sent.any(
        (entry) => entry.signal['candidate'] == 'phone-candidate',
      ),
    );

    await engine.startVideo();
    expect(peers.first.closed, isTrue);
    expect(signaling.stopped, contains('session-1'));
    expect(peers[1].receiveOnly, [
      WebRtcMediaKind.audio,
      WebRtcMediaKind.video,
    ]);

    await engine.stopAudio();
    expect(peers[1].closed, isTrue);
    expect(peers[2].receiveOnly, [WebRtcMediaKind.video]);

    await engine.stopVideo();
    expect(peers[2].closed, isTrue);
    expect(engine.state.sessionPhase, MediaSessionPhase.idle);
    expect(engine.state.audioPhase, MediaTrackPhase.off);
    expect(engine.state.videoPhase, MediaTrackPhase.off);
    expect(signaling.capabilityChecks, 1);

    await engine.dispose();
    expect(signaling.disposed, isTrue);
  });

  test('unavailable PC capability fails clearly without creating a peer',
      () async {
    final signaling = FakeSignaling(mediaAvailable: false);
    var peerCreations = 0;
    final engine = WebRtcMediaEngine(
      signalingFactory: (_) => signaling,
      peerFactory: () async {
        peerCreations += 1;
        return FakePeer(peerCreations);
      },
    );

    await engine.initialize(testContext);
    await expectLater(engine.startVideo(), throwsStateError);

    expect(peerCreations, 0);
    expect(signaling.created, isEmpty);
    expect(engine.state.sessionPhase, MediaSessionPhase.failed);
    expect(engine.state.videoPhase, MediaTrackPhase.failed);
    await engine.dispose();
  });

  test('peer creation failure still stops the server signaling session',
      () async {
    final signaling = FakeSignaling();
    final engine = WebRtcMediaEngine(
      signalingFactory: (_) => signaling,
      peerFactory: () async => throw StateError('native peer failed'),
    );

    await engine.initialize(testContext);
    await expectLater(engine.startAudio(), throwsStateError);

    expect(signaling.stopped, ['session-1']);
    expect(engine.state.sessionPhase, MediaSessionPhase.failed);
    await engine.dispose();
  });
}

final testContext = TrustedPcMediaContext(
  baseUri: Uri.parse('http://127.0.0.1:8765'),
  deviceId: 'test-phone',
  deviceToken: 'test-token',
);

class FakeSignaling implements MediaSignalingTransport {
  FakeSignaling({this.mediaAvailable = true});

  final bool mediaAvailable;
  final List<({bool audio, bool video})> created = [];
  final List<({String sessionId, Map<String, dynamic> signal})> sent = [];
  final List<String> stopped = [];
  final Map<String, Completer<Map<String, dynamic>>> _polls = {};
  final Map<String, Queue<Map<String, dynamic>>> _queued = {};
  int capabilityChecks = 0;
  bool disposed = false;

  @override
  Future<Map<String, dynamic>> capabilities() async {
    capabilityChecks += 1;
    return {
      'capabilities': {
        'engines': {
          'webrtc': {
            'signaling_available': true,
            'media_available': mediaAvailable,
          },
        },
      },
    };
  }

  @override
  Future<Map<String, dynamic>> createSession({
    required bool audio,
    required bool video,
  }) async {
    created.add((audio: audio, video: video));
    return {
      'session': {'session_id': 'session-${created.length}'},
    };
  }

  @override
  Future<Map<String, dynamic>> pollSignals(
    String sessionId, {
    int after = 0,
    int waitMs = 20000,
  }) {
    final queue = _queued[sessionId];
    if (queue != null && queue.isNotEmpty)
      return Future.value(queue.removeFirst());
    final poll = Completer<Map<String, dynamic>>();
    _polls[sessionId] = poll;
    return poll.future;
  }

  void deliver(String sessionId, List<Map<String, dynamic>> signals) {
    final response = <String, dynamic>{
      'signals': signals,
      'stopped': false,
    };
    final poll = _polls.remove(sessionId);
    if (poll != null) {
      poll.complete(response);
    } else {
      (_queued[sessionId] ??= Queue()).add(response);
    }
  }

  @override
  Future<Map<String, dynamic>> sendSignal(
    String sessionId,
    Map<String, dynamic> signal,
  ) async {
    sent.add((sessionId: sessionId, signal: signal));
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> status(String sessionId) async {
    return {
      'session': {'session_id': sessionId},
    };
  }

  @override
  Future<Map<String, dynamic>> stopSession(String sessionId) async {
    stopped.add(sessionId);
    _polls.remove(sessionId)?.complete({
      'signals': <Map<String, dynamic>>[],
      'stopped': true,
    });
    return {'ok': true, 'stopped': true};
  }

  @override
  void dispose() {
    disposed = true;
  }
}

class FakePeer implements WebRtcPeer {
  FakePeer(this.id);

  final int id;
  final List<WebRtcMediaKind> receiveOnly = [];
  final List<WebRtcIceCandidate> remoteCandidates = [];
  String? remoteAnswer;
  bool closed = false;
  void Function(WebRtcIceCandidate? candidate)? _onLocalCandidate;
  void Function(WebRtcPeerState state)? _onState;

  @override
  set onLocalCandidate(
    void Function(WebRtcIceCandidate? candidate)? callback,
  ) {
    _onLocalCandidate = callback;
  }

  @override
  set onState(void Function(WebRtcPeerState state)? callback) {
    _onState = callback;
  }

  @override
  set onTrack(void Function(RTCTrackEvent event)? _) {}

  @override
  Future<void> addReceiveOnly(WebRtcMediaKind kind) async {
    receiveOnly.add(kind);
  }

  @override
  Future<void> addRemoteCandidate(WebRtcIceCandidate candidate) async {
    remoteCandidates.add(candidate);
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<String> createOffer() async => 'phone-offer-$id';

  @override
  Future<void> setRemoteAnswer(String sdp) async {
    remoteAnswer = sdp;
  }

  void emitCandidate(WebRtcIceCandidate? candidate) {
    _onLocalCandidate?.call(candidate);
  }

  void emitState(WebRtcPeerState state) {
    _onState?.call(state);
  }
}

Future<void> eventually(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition was not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
