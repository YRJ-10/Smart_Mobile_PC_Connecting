/* Smart MPC - Live Camera / CCTV Viewer */

let peerConnection = null;
let iceQueue = [];
let rotation = 0;
let isMirrored = false;
let isAlwaysOnTop = false;
let idleTimer = null;

const camVideo = document.getElementById("camVideo");
const standbyOverlay = document.getElementById("standbyOverlay");
const standbyText = document.getElementById("standbyText");
const statusBadge = document.getElementById("statusBadge");
const statusLabel = document.getElementById("statusLabel");
const toolbar = document.getElementById("toolbar");
const toast = document.getElementById("toast");
const snapshotCanvas = document.getElementById("snapshotCanvas");

const btnAlwaysOnTop = document.getElementById("btnAlwaysOnTop");
const btnRotate = document.getElementById("btnRotate");
const btnMirror = document.getElementById("btnMirror");
const btnSwitchCam = document.getElementById("btnSwitchCam");
const btnCapture = document.getElementById("btnCapture");
const btnFullscreen = document.getElementById("btnFullscreen");
const btnRequestStream = document.getElementById("btnRequestStream");

function updateVideoTransform() {
  const scale = isMirrored ? -1 : 1;
  const isPerpendicular = rotation === 90 || rotation === 270;
  if (isPerpendicular) {
    camVideo.style.width = `${window.innerHeight}px`;
    camVideo.style.height = `${window.innerWidth}px`;
  } else {
    camVideo.style.width = "100%";
    camVideo.style.height = "100%";
  }
  camVideo.style.transform = `rotate(${rotation}deg) scaleX(${scale})`;
}

function setStatus(state, label) {
  statusBadge.className = `status-badge ${state}`;
  statusLabel.textContent = label;
}

function showToast(message) {
  toast.textContent = message;
  toast.classList.remove("hidden");
  setTimeout(() => {
    toast.classList.add("hidden");
  }, 3000);
}

function resetIdleTimer() {
  toolbar.classList.remove("idle");
  clearTimeout(idleTimer);
  idleTimer = setTimeout(() => {
    if (camVideo.srcObject) {
      toolbar.classList.add("idle");
    }
  }, 3500);
}

window.addEventListener("mousemove", resetIdleTimer);

async function handleSignal(signal) {
  if (!signal || !signal.type) return;

  switch (signal.type) {
    case "CAM_OFFER":
      await handleOffer(signal);
      break;

    case "CAM_ICE":
      await handleRemoteIce(signal);
      break;

    case "CAM_STOP":
    case "CAM_DISCONNECTED":
      handleStop(signal.type === "CAM_DISCONNECTED" ? "Ponsel terputus" : "Streaming dihentikan oleh HP");
      break;
  }
}

async function handleOffer(signal) {
  try {
    setStatus("connecting", "Menghubungkan...");
    standbyText.textContent = "Menghubungkan ke kamera ponsel...";
    rotation = 0;
    updateVideoTransform();

    if (peerConnection) {
      peerConnection.close();
      peerConnection = null;
    }

    iceQueue = [];

    peerConnection = new RTCPeerConnection({
      iceServers: [
        { urls: "stun:stun.l.google.com:19302" },
        { urls: "stun:stun1.l.google.com:19302" }
      ]
    });

    peerConnection.ontrack = (event) => {
      if (event.streams && event.streams[0]) {
        camVideo.srcObject = event.streams[0];
        standbyOverlay.classList.add("hidden");
        setStatus("live", "Live");
        resetIdleTimer();
      }
    };

    peerConnection.onicecandidate = (event) => {
      if (event.candidate) {
        window.smartMpc.sendCamSignal({
          type: "CAM_ICE",
          candidate: event.candidate.candidate,
          sdpMid: event.candidate.sdpMid,
          sdpMLineIndex: event.candidate.sdpMLineIndex
        });
      }
    };

    peerConnection.onconnectionstatechange = () => {
      const state = peerConnection.connectionState;
      if (state === "connected") {
        setStatus("live", "Live");
        standbyOverlay.classList.add("hidden");
      } else if (state === "disconnected" || state === "failed" || state === "closed") {
        handleStop("Koneksi kamera terputus");
      }
    };

    await peerConnection.setRemoteDescription(
      new RTCSessionDescription({
        type: signal.sdpType || "offer",
        sdp: signal.sdp
      })
    );

    // Drain queued ICE candidates
    while (iceQueue.length > 0) {
      const cand = iceQueue.shift();
      try {
        await peerConnection.addIceCandidate(cand);
      } catch (err) {
        console.warn("[CamViewer] Error adding queued ICE candidate:", err);
      }
    }

    const answer = await peerConnection.createAnswer();
    await peerConnection.setLocalDescription(answer);

    window.smartMpc.sendCamSignal({
      type: "CAM_ANSWER",
      sdp: answer.sdp,
      sdpType: answer.type
    });
  } catch (err) {
    console.error("[CamViewer] Offer handling failed:", err);
    handleStop("Gagal negosiasi WebRTC: " + err.message);
  }
}

async function handleRemoteIce(signal) {
  if (!signal.candidate) return;
  const candidate = new RTCIceCandidate({
    candidate: signal.candidate,
    sdpMid: signal.sdpMid,
    sdpMLineIndex: signal.sdpMLineIndex
  });

  if (peerConnection && peerConnection.remoteDescription) {
    try {
      await peerConnection.addIceCandidate(candidate);
    } catch (err) {
      console.warn("[CamViewer] Error adding remote ICE candidate:", err);
    }
  } else {
    iceQueue.push(candidate);
  }
}

function handleStop(reason = "Streaming dihentikan") {
  if (peerConnection) {
    peerConnection.close();
    peerConnection = null;
  }
  iceQueue = [];
  camVideo.srcObject = null;
  standbyText.textContent = reason;
  standbyOverlay.classList.remove("hidden");
  setStatus("", "Standby");
  toolbar.classList.remove("idle");
}

// Button Events
btnRotate.addEventListener("click", () => {
  rotation = (rotation + 90) % 360;
  updateVideoTransform();
});

btnMirror.addEventListener("click", () => {
  isMirrored = !isMirrored;
  btnMirror.classList.toggle("active", isMirrored);
  updateVideoTransform();
});

btnSwitchCam.addEventListener("click", () => {
  window.smartMpc.sendCamSignal({ type: "CAM_SWITCH" });
  showToast("Mengganti lensa kamera...");
});

btnAlwaysOnTop.addEventListener("click", async () => {
  isAlwaysOnTop = !isAlwaysOnTop;
  const active = await window.smartMpc.setCamAlwaysOnTop(isAlwaysOnTop);
  btnAlwaysOnTop.classList.toggle("active", active);
  showToast(active ? "Pin Selalu di Atas: Aktif" : "Pin Selalu di Atas: Nonaktif");
});

btnCapture.addEventListener("click", async () => {
  if (!camVideo.srcObject || camVideo.videoWidth === 0) {
    showToast("Tidak ada video untuk diambil fotonya");
    return;
  }

  const isPerpendicular = rotation === 90 || rotation === 270;
  snapshotCanvas.width = isPerpendicular ? camVideo.videoHeight : camVideo.videoWidth;
  snapshotCanvas.height = isPerpendicular ? camVideo.videoWidth : camVideo.videoHeight;
  const ctx = snapshotCanvas.getContext("2d");

  // Apply current rotation/mirror to captured photo if rotated/mirrored
  ctx.save();
  ctx.translate(snapshotCanvas.width / 2, snapshotCanvas.height / 2);
  ctx.rotate((rotation * Math.PI) / 180);
  ctx.scale(isMirrored ? -1 : 1, 1);
  ctx.drawImage(
    camVideo,
    -camVideo.videoWidth / 2,
    -camVideo.videoHeight / 2,
    camVideo.videoWidth,
    camVideo.videoHeight
  );
  ctx.restore();

  const dataUrl = snapshotCanvas.toDataURL("image/png");
  const res = await window.smartMpc.saveCamSnapshot(dataUrl);
  if (res && res.ok) {
    showToast(`📸 Foto disimpan: ${res.filename} (Tersalin ke clipboard!)`);
  } else {
    showToast("Gagal menyimpan foto: " + (res?.error || "Unknown"));
  }
});

btnFullscreen.addEventListener("click", () => {
  if (!document.fullscreenElement) {
    document.documentElement.requestFullscreen().catch(() => {});
  } else {
    document.exitFullscreen().catch(() => {});
  }
});

btnRequestStream.addEventListener("click", () => {
  setStatus("connecting", "Meminta...");
  standbyText.textContent = "Mengirim sinyal permintaan streaming ke ponsel...";
  window.smartMpc.sendCamSignal({ type: "CAM_REQUEST" });
  showToast("Permintaan streaming dikirim ke HP");
});

// Setup
window.addEventListener("resize", updateVideoTransform);
window.smartMpc.onCamSignal(handleSignal);
window.smartMpc.sendCamSignal({ type: "CAM_REQUEST" });
resetIdleTimer();
