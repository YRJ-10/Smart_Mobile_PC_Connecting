import { app, BrowserWindow } from "electron";

import { MediaWorkerProcess } from "./media-worker-process.mjs";

const SESSION_ID = "30000000-0000-0000-0000-000000000001";
const PROBE_TIMEOUT_MS = 20_000;

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
    await receiverWindow.loadURL(
      "data:text/html,<html><body>Smart MPC video transport probe</body></html>"
    );
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
              reject(new Error("Video receiver peer failed"));
            }
          };
        });
        peer.addTransceiver("video", { direction: "recvonly" });
        const offer = await peer.createOffer();
        await peer.setLocalDescription(offer);
        if (peer.iceGatheringState !== "complete") {
          await new Promise((resolve) => {
            peer.onicegatheringstatechange = () => {
              if (peer.iceGatheringState === "complete") resolve();
            };
          });
        }
        window.smartMpcVideoProbe = { peer, trackPromise, connectedPromise };
        return peer.localDescription.sdp;
      })()
    `, true);

    await worker.openSession({
      session_id: SESSION_ID,
      tracks: { audio: false, video: true }
    });
    const serverDescription = collectServerDescription(worker);
    await worker.sendSignal(SESSION_ID, { kind: "offer", sdp: offerSdp });
    const { answer, candidates } = await withTimeout(
      serverDescription,
      PROBE_TIMEOUT_MS,
      "PC video answer"
    );

    const result = await receiverWindow.webContents.executeJavaScript(`
      (async () => {
        const probe = window.smartMpcVideoProbe;
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
          timeout(probe.trackPromise, "Remote desktop video track"),
          timeout(probe.connectedPromise, "Video peer connection")
        ]);

        const video = document.createElement("video");
        video.autoplay = true;
        video.muted = true;
        video.playsInline = true;
        video.srcObject = new MediaStream([track]);
        document.body.append(video);
        await video.play();

        const decoded = await timeout(new Promise((resolve) => {
          const startedAt = Date.now();
          let latest = null;
          const inspect = async () => {
            const stats = await probe.peer.getStats(track);
            const inbound = [...stats.values()].find((entry) => (
              entry.type === "inbound-rtp" && entry.kind === "video"
            ));
            if ((inbound?.framesDecoded ?? 0) > 0 && video.videoWidth > 0) {
              const codec = stats.get(inbound.codecId);
              latest = {
                framesDecoded: inbound.framesDecoded,
                codec: codec?.mimeType ?? "",
                width: video.videoWidth,
                height: video.videoHeight
              };
            }
            if (latest?.framesDecoded >= 10 && latest.width >= 1280) {
              resolve(latest);
              return;
            }
            if (latest && Date.now() - startedAt >= 5000) {
              resolve(latest);
              return;
            }
            setTimeout(inspect, 50);
          };
          inspect();
        }), "Decoded desktop frame");

        return {
          connected: probe.peer.connectionState === "connected",
          remoteVideoTrack: track.kind === "video" && track.readyState === "live",
          decodedFrame: decoded.framesDecoded > 0,
          codec: decoded.codec,
          width: decoded.width,
          height: decoded.height
        };
      })()
    `, true);
    const workerVideo = worker.state().video;

    await receiverWindow.webContents.executeJavaScript(`
      window.smartMpcVideoProbe?.peer.close()
    `, true);
    await worker.closeSession(SESSION_ID);
    return { ...result, workerVideo };
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
        if (!answer) reject(new Error("PC video worker returned no SDP answer"));
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
    const codec = result.codec.toLowerCase();
    app.exit(
      result.connected &&
        result.remoteVideoTrack &&
        result.decodedFrame &&
        result.width >= 1280 &&
        (codec === "video/h264" || codec === "video/vp8") &&
        result.workerVideo.active &&
        result.workerVideo.encoding?.max_framerate === 30
        ? 0
        : 1
    );
  } catch (error) {
    process.stderr.write(`Video transport probe failed: ${error.stack ?? error.message}\n`);
    app.exit(1);
  }
});
