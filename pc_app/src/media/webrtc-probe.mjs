import { app, BrowserWindow } from "electron";

const PROBE_TIMEOUT_MS = 10_000;

async function runProbe() {
  const window = new BrowserWindow({
    show: false,
    webPreferences: {
      contextIsolation: true,
      sandbox: true
    }
  });

  try {
    await window.loadURL("data:text/html,<html><body>Smart MPC WebRTC probe</body></html>");
    return await window.webContents.executeJavaScript(`
      (async () => {
        const timeoutMs = ${PROBE_TIMEOUT_MS};
        const withTimeout = (promise, label) => Promise.race([
          promise,
          new Promise((_, reject) => setTimeout(
            () => reject(new Error(label + " timed out")),
            timeoutMs
          ))
        ]);
        const waitForIce = (peer) => {
          if (peer.iceGatheringState === "complete") return Promise.resolve();
          return new Promise((resolve) => {
            const listener = () => {
              if (peer.iceGatheringState !== "complete") return;
              peer.removeEventListener("icegatheringstatechange", listener);
              resolve();
            };
            peer.addEventListener("icegatheringstatechange", listener);
          });
        };

        if (typeof RTCPeerConnection !== "function") {
          throw new Error("RTCPeerConnection is unavailable in Electron renderer");
        }

        const audioCodecs = (RTCRtpSender.getCapabilities("audio")?.codecs ?? [])
          .map((codec) => codec.mimeType.toLowerCase());
        const videoCodecs = (RTCRtpSender.getCapabilities("video")?.codecs ?? [])
          .map((codec) => codec.mimeType.toLowerCase());
        const offerer = new RTCPeerConnection({ iceServers: [] });
        const answerer = new RTCPeerConnection({ iceServers: [] });
        let incomingChannel = null;

        try {
          const echoed = new Promise((resolve, reject) => {
            answerer.ondatachannel = (event) => {
              incomingChannel = event.channel;
              incomingChannel.onmessage = (message) => incomingChannel.send(message.data);
            };

            const channel = offerer.createDataChannel("smart-mpc-probe", {
              ordered: true
            });
            channel.onerror = () => reject(new Error("WebRTC data channel failed"));
            channel.onmessage = (message) => resolve(message.data);
            channel.onopen = () => channel.send("smart-mpc-webrtc-probe");
          });

          const offer = await offerer.createOffer();
          await offerer.setLocalDescription(offer);
          await withTimeout(waitForIce(offerer), "Offer ICE gathering");
          await answerer.setRemoteDescription(offerer.localDescription);

          const answer = await answerer.createAnswer();
          await answerer.setLocalDescription(answer);
          await withTimeout(waitForIce(answerer), "Answer ICE gathering");
          await offerer.setRemoteDescription(answerer.localDescription);

          const echoPayload = await withTimeout(echoed, "Data channel echo");
          if (echoPayload !== "smart-mpc-webrtc-probe") {
            throw new Error("WebRTC data channel returned an invalid payload");
          }

          return {
            runtime: navigator.userAgent,
            dataChannelConnected: true,
            hostCandidatesOnly: true,
            audioCodecs: [...new Set(audioCodecs)],
            videoCodecs: [...new Set(videoCodecs)],
            opusAvailable: audioCodecs.includes("audio/opus"),
            vp8Available: videoCodecs.includes("video/vp8"),
            h264Available: videoCodecs.includes("video/h264")
          };
        } finally {
          incomingChannel?.close();
          offerer.close();
          answerer.close();
        }
      })()
    `, true);
  } finally {
    window.destroy();
  }
}

app.whenReady().then(async () => {
  try {
    const result = await runProbe();
    process.stdout.write(`${JSON.stringify(result)}\n`);
    app.exit(result.dataChannelConnected && result.opusAvailable ? 0 : 1);
  } catch (error) {
    process.stderr.write(`WebRTC probe failed: ${error.stack ?? error.message}\n`);
    app.exit(1);
  }
});
