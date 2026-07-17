const bridge = window.smartMpcMediaWorker;
const sessions = new Map();

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
      bridge.sendEvent({ type: "worker-stopped" });
      return;
    }
    throw new Error(`Unsupported media worker command: ${command.type}`);
  } catch (error) {
    const sessionId = String(command.session_id ?? command.session?.session_id ?? "");
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

  sessions.set(sessionId, { peer, tracks: session.tracks });
  bridge.sendEvent({ type: "session-opened", session_id: sessionId });
}

async function handleSignal(sessionId, signal) {
  const session = sessions.get(sessionId);
  if (!session) throw new Error("Media session is not open in worker");

  if (signal.kind === "offer") {
    await session.peer.setRemoteDescription({ type: "offer", sdp: signal.sdp });
    const answer = await session.peer.createAnswer();
    await session.peer.setLocalDescription(answer);
    bridge.sendEvent({
      type: "server-signal",
      session_id: sessionId,
      signal: { kind: "answer", sdp: session.peer.localDescription.sdp }
    });
    return;
  }
  if (signal.kind === "ice-candidate") {
    await session.peer.addIceCandidate({
      candidate: signal.candidate,
      sdpMid: signal.sdp_mid,
      sdpMLineIndex: signal.sdp_mline_index
    });
    return;
  }
  if (signal.kind === "ice-complete") {
    await session.peer.addIceCandidate(null);
    return;
  }
  throw new Error(`Unsupported client signal: ${signal.kind}`);
}

function closeSession(sessionId) {
  const session = sessions.get(sessionId);
  if (!session) return;
  session.peer.onicecandidate = null;
  session.peer.onconnectionstatechange = null;
  session.peer.close();
  sessions.delete(sessionId);
  bridge.sendEvent({ type: "session-closed", session_id: sessionId });
}

bridge.ready();
