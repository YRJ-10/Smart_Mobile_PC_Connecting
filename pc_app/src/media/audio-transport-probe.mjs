import { app, BrowserWindow } from "electron";

import { MediaWorkerProcess } from "./media-worker-process.mjs";

const SESSION_ID = "20000000-0000-0000-0000-000000000001";
const PROBE_TIMEOUT_MS = 15_000;

async function runProbe() {
  const receiverWindow = new BrowserWindow({
    show: false,
    webPreferences: {
      contextIsolation: true,
      sandbox: true,
      backgroundThrottling: false
    }
  });
  const worker = new MediaWorkerProcess();

  try {
    await receiverWindow.loadURL("data:text/html,<html><body>Smart MPC audio transport probe</body></html>");
    const offerSdp = await receiverWindow.webContents.executeJavaScript(`
      (async () => {
        const peer = new RTCPeerConnection({ iceServers: [] });
        const trackPromise = new Promise((resolve) => {
          peer.ontrack = (event) => resolve(event.track);
        });
        const connectedPromise = new Promise((resolve, reject) => {
          peer.onconnectionstatechange = () => {
            if (peer.connectionState === "connected") resolve(true);
            if (peer.connectionState === "failed") {
              reject(new Error("Audio receiver peer failed"));
            }
          };
        });
        peer.addTransceiver("audio", { direction: "recvonly" });
        const offer = await peer.createOffer();
        await peer.setLocalDescription(offer);
        if (peer.iceGatheringState !== "complete") {
          await new Promise((resolve) => {
            peer.onicegatheringstatechange = () => {
              if (peer.iceGatheringState === "complete") resolve();
            };
          });
        }
        window.smartMpcAudioProbe = { peer, trackPromise, connectedPromise };
        return peer.localDescription.sdp;
      })()
    `, true);

    await worker.openSession({
      session_id: SESSION_ID,
      tracks: { audio: true, video: false }
    });
    const serverDescription = collectServerDescription(worker);
    await worker.sendSignal(SESSION_ID, { kind: "offer", sdp: offerSdp });
    const { answer, candidates } = await withTimeout(
      serverDescription,
      PROBE_TIMEOUT_MS,
      "PC audio answer"
    );

    const result = await receiverWindow.webContents.executeJavaScript(`
      (async () => {
        const probe = window.smartMpcAudioProbe;
        const timeout = (promise, label) => Promise.race([
          promise,
          new Promise((_, reject) => setTimeout(
            () => reject(new Error(label + " timed out")),
            ${PROBE_TIMEOUT_MS}
          ))
        ]);
        const answer = ${JSON.stringify(answer)};
        const candidates = ${JSON.stringify(candidates)};
        await probe.peer.setRemoteDescription({ type: "answer", sdp: answer });
        for (const candidate of candidates) {
          await probe.peer.addIceCandidate(candidate);
        }
        const [track] = await Promise.all([
          timeout(probe.trackPromise, "Remote system audio track"),
          timeout(probe.connectedPromise, "Audio peer connection")
        ]);
        const settings = track.getSettings();
        return {
          connected: probe.peer.connectionState === "connected",
          remoteAudioTrack: track.kind === "audio" && track.readyState === "live",
          answerHasOpus48k: /a=rtpmap:\\d+ opus\\/48000/i.test(answer),
          trackSettings: settings
        };
      })()
    `, true);

    await receiverWindow.webContents.executeJavaScript(`
      window.smartMpcAudioProbe?.peer.close()
    `, true);
    await worker.closeSession(SESSION_ID);
    return result;
  } finally {
    await worker.stop().catch(() => {});
    if (!receiverWindow.isDestroyed()) receiverWindow.destroy();
  }
}

function collectServerDescription(worker) {
  return new Promise((resolve, reject) => {
    let answer = "";
    const candidates = [];
    const onSignal = ({ session_id: sessionId, signal }) => {
      if (sessionId !== SESSION_ID) return;
      if (signal.kind === "answer") answer = signal.sdp;
      if (signal.kind === "ice-candidate") {
        candidates.push({
          candidate: signal.candidate,
          sdpMid: signal.sdp_mid,
          sdpMLineIndex: signal.sdp_mline_index
        });
      }
      if (signal.kind === "error") {
        cleanup();
        reject(new Error(signal.message));
      }
      if (signal.kind === "ice-complete") {
        cleanup();
        if (!answer) reject(new Error("PC audio worker returned no SDP answer"));
        else resolve({ answer, candidates });
      }
    };
    const onWorkerError = ({ session_id: sessionId, error }) => {
      if (sessionId !== SESSION_ID) return;
      cleanup();
      reject(new Error(error));
    };
    const cleanup = () => {
      worker.removeListener("server-signal", onSignal);
      worker.removeListener("worker-error", onWorkerError);
    };
    worker.on("server-signal", onSignal);
    worker.on("worker-error", onWorkerError);
  });
}

function withTimeout(promise, timeoutMs, label) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(
      () => reject(new Error(`${label} timed out`)),
      timeoutMs
    );
    promise.then(
      (value) => {
        clearTimeout(timeout);
        resolve(value);
      },
      (error) => {
        clearTimeout(timeout);
        reject(error);
      }
    );
  });
}

app.whenReady().then(async () => {
  try {
    const result = await runProbe();
    process.stdout.write(`${JSON.stringify(result)}\n`);
    app.exit(
      result.connected && result.remoteAudioTrack && result.answerHasOpus48k
        ? 0
        : 1
    );
  } catch (error) {
    process.stderr.write(`Audio transport probe failed: ${error.stack ?? error.message}\n`);
    app.exit(1);
  }
});
