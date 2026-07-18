import assert from "node:assert/strict";
import test from "node:test";

import { SystemAudioCapture } from "../renderer/media-worker/system-audio-capture.js";

test("system audio capture is shared and stops after its last session", async () => {
  const sourceAudio = new FakeTrack("audio", "source-audio");
  const sourceVideo = new FakeTrack("video", "source-video");
  const stream = new FakeStream([sourceAudio, sourceVideo]);
  let displayRequests = 0;
  let requestedConstraints = null;
  const capture = new SystemAudioCapture({
    getDisplayMedia: async (constraints) => {
      displayRequests += 1;
      requestedConstraints = constraints;
      return stream;
    }
  });

  const [first, second] = await Promise.all([
    capture.acquire("session-1"),
    capture.acquire("session-2")
  ]);

  assert.equal(displayRequests, 1);
  assert.deepEqual(requestedConstraints.audio, {
    autoGainControl: false,
    echoCancellation: false,
    latency: { ideal: 0.01, max: 0.02 },
    noiseSuppression: false,
    sampleRate: { ideal: 48000 }
  });
  assert.equal(sourceVideo.stopped, true);
  assert.equal(first.contentHint, "music");
  assert.equal(second.contentHint, "music");
  assert.deepEqual(capture.state(), {
    active: true,
    sessions: 2,
    settings: { sampleRate: 48000, channelCount: 2 }
  });

  capture.release("session-1");
  assert.equal(first.stopped, true);
  assert.equal(sourceAudio.stopped, false);
  assert.equal(capture.state().sessions, 1);

  capture.release("session-2");
  assert.equal(second.stopped, true);
  assert.equal(sourceAudio.stopped, true);
  assert.equal(capture.state().active, false);
});

test("capture rejects a display stream without Windows loopback audio", async () => {
  const video = new FakeTrack("video", "video-only");
  const capture = new SystemAudioCapture({
    getDisplayMedia: async () => new FakeStream([video])
  });

  await assert.rejects(
    capture.acquire("session-1"),
    /did not provide a system audio track/
  );
  assert.equal(video.stopped, true);
  assert.equal(capture.state().active, false);
});

test("unexpected source end reports affected sessions and releases clones", async () => {
  const sourceAudio = new FakeTrack("audio", "source-audio");
  const stream = new FakeStream([sourceAudio]);
  let affectedSessions = null;
  const capture = new SystemAudioCapture({
    getDisplayMedia: async () => stream,
    onSourceEnded: (sessionIds) => {
      affectedSessions = sessionIds;
    }
  });

  const clone = await capture.acquire("session-1");
  sourceAudio.onended();

  assert.deepEqual(affectedSessions, ["session-1"]);
  assert.equal(clone.stopped, true);
  assert.equal(capture.state().active, false);
});

class FakeStream {
  constructor(tracks) {
    this.tracks = tracks;
  }

  getTracks() {
    return this.tracks;
  }

  getAudioTracks() {
    return this.tracks.filter((track) => track.kind === "audio");
  }

  getVideoTracks() {
    return this.tracks.filter((track) => track.kind === "video");
  }
}

class FakeTrack {
  constructor(kind, id) {
    this.kind = kind;
    this.id = id;
    this.readyState = "live";
    this.contentHint = "";
    this.stopped = false;
    this.onended = null;
  }

  clone() {
    return new FakeTrack(this.kind, `${this.id}-clone`);
  }

  stop() {
    this.stopped = true;
    this.readyState = "ended";
  }

  getSettings() {
    return { sampleRate: 48000, channelCount: 2 };
  }
}
