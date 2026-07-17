import { SystemAudioCapture } from "./system-audio-capture.js";

const bridge = window.smartMpcMediaWorker;
const sessions = new Map();
const systemAudio = new SystemAudioCapture({
  onSourceEnded(sessionIds) {
    for (const sessionId of sessionIds) {
      bridge.sendEvent({
        type: "worker-error",
        session_id: sessionId,
        error: "Windows system audio capture ended unexpectedly"
      });
    }
  }
});

bridge.onCommand(async (command) => {
  try {
    if (command.type === "session-open") {
      await openSession(command.session);
      return;
    }
    if (command.type === "signal") {
      await handleSignal(command.session_id, command.signal);
      return;
    }
    if (command.type === "session-close") {
      closeSession(command.session_id);
      return;
    }
    if (command.type === "shutdown") {
      for (const sessionId of [...sessions.keys()]) closeSession(sessionId);
      systemAudio.stop();
      bridge.sendEvent({ type: "worker-stopped" });
      return;
    }
    throw new Error(`Unsupported media worker command: ${command.type}`);
  } catch (error) {
    const sessionId = String(command.session_id ?? command.session?.session_id ?? "");
    if (sessionId && sessions.has(sessionId)) closeSession(sessionId);
    bridge.sendEvent({
      type: "worker-error",
      session_id: sessionId,
      error: error.message
    });
  }
});

async function openSession(session) {
  const sessionId = String(session.session_id ?? "");
  if (!sessionId || sessions.has(sessionId)) return;

  const peer = new RTCPeerConnection({ iceServers: [] });
  peer.onicecandidate = (event) => {
    bridge.sendEvent({
      type: "server-signal",
      session_id: sessionId,
      signal: event.candidate
        ? {
            kind: "ice-candidate",
            candidate: event.candidate.candidate,
            sdp_mid: event.candidate.sdpMid,
            sdp_mline_index: event.candidate.sdpMLineIndex
          }
        : { kind: "ice-complete" }
    });
  };
  peer.onconnectionstatechange = () => {
    bridge.sendEvent({
      type: "session-state",
      session_id: sessionId,
      state: peer.connectionState
    });
  };

  sessions.set(sessionId, {
    peer,
    tracks: session.tracks,
    audioTrack: null,
    closed: false,
    remoteDescriptionSet: false,
    pendingCandidates: []
  });
  bridge.sendEvent({ type: "session-opened", session_id: sessionId });
}

async function handleSignal(sessionId, signal) {
  const session = sessions.get(sessionId);
  if (!session) throw new Error("Media session is not open in worker");

  if (signal.kind === "offer") {
    await session.peer.setRemoteDescription({ type: "offer", sdp: signal.sdp });
    if (!isActiveSession(sessionId, session)) return;
    session.remoteDescriptionSet = true;
    for (const candidate of session.pendingCandidates) {
      await session.peer.addIceCandidate(candidate);
    }
    session.pendingCandidates.length = 0;
    if (session.tracks.audio) {
      const attached = await attachSystemAudio(sessionId, session);
      if (!attached) return;
    }
    if (!isActiveSession(sessionId, session)) return;
    const answer = await session.peer.createAnswer();
    await session.peer.setLocalDescription(answer);
    if (!isActiveSession(sessionId, session)) return;
    bridge.sendEvent({
      type: "server-signal",
      session_id: sessionId,
      signal: { kind: "answer", sdp: session.peer.localDescription.sdp }
    });
    return;
  }
  if (signal.kind === "ice-candidate") {
    const candidate = {
      candidate: signal.candidate,
      sdpMid: signal.sdp_mid,
      sdpMLineIndex: signal.sdp_mline_index
    };
    if (session.remoteDescriptionSet) {
      await session.peer.addIceCandidate(candidate);
    } else {
      session.pendingCandidates.push(candidate);
    }
    return;
  }
  if (signal.kind === "ice-complete") {
    if (session.remoteDescriptionSet) await session.peer.addIceCandidate(null);
    else session.pendingCandidates.push(null);
    return;
  }
  throw new Error(`Unsupported client signal: ${signal.kind}`);
}

function closeSession(sessionId) {
  const session = sessions.get(sessionId);
  if (!session) return;
  session.closed = true;
  session.peer.onicecandidate = null;
  session.peer.onconnectionstatechange = null;
  session.peer.close();
  systemAudio.release(sessionId);
  sessions.delete(sessionId);
  bridge.sendEvent({
    type: "audio-capture-state",
    session_id: sessionId,
    state: systemAudio.state()
  });
  bridge.sendEvent({ type: "session-closed", session_id: sessionId });
}

async function attachSystemAudio(sessionId, session) {
  const transceiver = session.peer.getTransceivers().find((value) => (
    value.receiver.track.kind === "audio"
  ));
  if (!transceiver) throw new Error("Android offer has no audio transceiver");

  const track = await systemAudio.acquire(sessionId);
  if (!isActiveSession(sessionId, session)) {
    systemAudio.release(sessionId);
    return false;
  }
  session.audioTrack = track;
  await transceiver.sender.replaceTrack(track);
  transceiver.direction = "sendonly";
  const opus = (RTCRtpSender.getCapabilities("audio")?.codecs ?? []).filter(
    (codec) => codec.mimeType.toLowerCase() === "audio/opus"
  );
  if (!opus.length) throw new Error("Chromium Opus encoder is unavailable");
  transceiver.setCodecPreferences(opus);
  bridge.sendEvent({
    type: "audio-capture-state",
    session_id: sessionId,
    state: systemAudio.state()
  });
  return true;
}

function isActiveSession(sessionId, session) {
  return !session.closed && sessions.get(sessionId) === session;
}

bridge.ready();
