import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRtcProbeResult {
  const WebRtcProbeResult({
    required this.dataChannelConnected,
    required this.echoPayload,
  });

  final bool dataChannelConnected;
  final String echoPayload;
}

class WebRtcProbe {
  static const _probePayload = 'smart-mpc-webrtc-probe';

  static Future<WebRtcProbeResult> run() async {
    RTCPeerConnection? offerer;
    RTCPeerConnection? answerer;
    RTCDataChannel? outgoingChannel;
    RTCDataChannel? incomingChannel;
    final echo = Completer<String>();

    try {
      const configuration = <String, dynamic>{
        'iceServers': <Map<String, dynamic>>[],
        'sdpSemantics': 'unified-plan',
      };
      offerer = await createPeerConnection(configuration);
      answerer = await createPeerConnection(configuration);

      offerer.onIceCandidate = (candidate) {
        unawaited(answerer?.addCandidate(candidate));
      };
      answerer.onIceCandidate = (candidate) {
        unawaited(offerer?.addCandidate(candidate));
      };

      answerer.onDataChannel = (channel) {
        incomingChannel = channel;
        channel.onMessage = (message) {
          unawaited(channel.send(RTCDataChannelMessage(message.text)));
        };
      };

      outgoingChannel = await offerer.createDataChannel(
        'smart-mpc-probe',
        RTCDataChannelInit()..id = 1,
      );
      outgoingChannel.onDataChannelState = (state) {
        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          unawaited(
            outgoingChannel?.send(RTCDataChannelMessage(_probePayload)),
          );
        }
      };
      outgoingChannel.onMessage = (message) {
        if (!echo.isCompleted) echo.complete(message.text);
      };

      final offer = await offerer.createOffer();
      await answerer.setRemoteDescription(offer);
      final answer = await answerer.createAnswer();
      await offerer.setLocalDescription(offer);
      await answerer.setLocalDescription(answer);
      await offerer.setRemoteDescription(answer);

      final payload = await echo.future.timeout(const Duration(seconds: 10));
      if (payload != _probePayload) {
        throw StateError('WebRTC data channel returned an invalid payload');
      }
      return WebRtcProbeResult(
        dataChannelConnected: true,
        echoPayload: payload,
      );
    } finally {
      await outgoingChannel?.close();
      await incomingChannel?.close();
      await offerer?.close();
      await answerer?.close();
    }
  }
}
