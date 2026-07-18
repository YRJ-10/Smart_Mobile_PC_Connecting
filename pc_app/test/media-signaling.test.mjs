import assert from "node:assert/strict";
import test from "node:test";

import {
  MediaSignalingError,
  MediaSignalingService
} from "../src/media/media-signaling-service.mjs";
import { isMediaSignalingRoute } from "../src/media/media-signaling-routes.mjs";

test("capabilities stay local and do not advertise media before worker readiness", () => {
  const signaling = new MediaSignalingService();
  const capabilities = signaling.capabilities();

  assert.equal(capabilities.local_only, true);
  assert.deepEqual(capabilities.ice_servers, []);
  assert.equal(capabilities.engines.webrtc.signaling_available, true);
  assert.equal(capabilities.engines.webrtc.media_available, false);
  assert.deepEqual(capabilities.engines.webrtc.audio.codecs, ["opus"]);
  assert.deepEqual(capabilities.engines.webrtc.video, {
    codecs: ["H264", "VP8"],
    source: "primary-display",
    max_frame_rate: 30,
    congestion_control: "webrtc-native"
  });
});

test("a new session replaces the previous session owned by the same device", () => {
  const signaling = readySignaling();
  const first = signaling.createSession("phone-1", {
    engine: "webrtc",
    tracks: { audio: true }
  });
  const second = signaling.createSession("phone-1", {
    engine: "webrtc",
    tracks: { video: true }
  });

  assert.notEqual(first.session_id, second.session_id);
  assert.equal(signaling.state().active_sessions, 1);
  assert.throws(
    () => signaling.status("phone-1", first.session_id),
    (error) => error instanceof MediaSignalingError && error.status === 404
  );
});

test("client signals are validated, sequenced, and isolated by owner", () => {
  const signaling = readySignaling();
  const session = signaling.createSession("phone-1", {
    tracks: { audio: true, video: true }
  });

  const signal = signaling.enqueueClientSignal("phone-1", session.session_id, {
    kind: "offer",
    sdp: "v=0"
  });
  assert.equal(signal.sequence, 1);
  assert.equal(signal.sdp, "v=0\r\n");
  assert.equal(signaling.takeClientSignals(session.session_id).length, 1);
  assert.throws(
    () => signaling.enqueueClientSignal("phone-2", session.session_id, {
      kind: "offer",
      sdp: "v=0"
    }),
    (error) => error instanceof MediaSignalingError && error.status === 404
  );
});

test("SDP line endings are normalized and retain the required terminator", () => {
  const signaling = readySignaling();
  const session = signaling.createSession("phone-1", {
    tracks: { audio: true }
  });

  const offer = signaling.enqueueClientSignal("phone-1", session.session_id, {
    kind: "offer",
    sdp: "v=0\ns=-\n"
  });
  assert.equal(offer.sdp, "v=0\r\ns=-\r\n");

  const answer = signaling.publishServerSignal(session.session_id, {
    kind: "answer",
    sdp: "v=0\r\ns=-"
  });
  assert.equal(answer.sdp, "v=0\r\ns=-\r\n");
});

test("server signals wake a pending long poll and preserve sequence", async () => {
  const signaling = readySignaling();
  const session = signaling.createSession("phone-1", {
    tracks: { audio: true }
  });
  const pending = signaling.readServerSignals("phone-1", session.session_id, {
    after: 0,
    waitMs: 1000
  });

  signaling.publishServerSignal(session.session_id, {
    kind: "answer",
    sdp: "v=0"
  });
  const result = await pending;

  assert.equal(result.stopped, false);
  assert.equal(result.signals.length, 1);
  assert.equal(result.signals[0].sequence, 1);
  assert.equal(result.signals[0].kind, "answer");
});

test("stopping a session resolves pending long polls and removes state", async () => {
  const signaling = readySignaling();
  const session = signaling.createSession("phone-1", {
    tracks: { video: true }
  });
  const pending = signaling.readServerSignals("phone-1", session.session_id, {
    waitMs: 1000
  });

  signaling.stopSession("phone-1", session.session_id);
  const result = await pending;

  assert.equal(result.stopped, true);
  assert.equal(signaling.state().active_sessions, 0);
});

test("media route matcher excludes unrelated protected APIs", () => {
  assert.equal(isMediaSignalingRoute("/api/media/capabilities"), true);
  assert.equal(isMediaSignalingRoute("/api/media/sessions"), true);
  assert.equal(
    isMediaSignalingRoute("/api/media/sessions/00000000-0000-0000-0000-000000000000/signals"),
    true
  );
  assert.equal(isMediaSignalingRoute("/api/clipboard"), false);
});

function readySignaling() {
  const signaling = new MediaSignalingService();
  signaling.setWorkerReady(true);
  return signaling;
}
