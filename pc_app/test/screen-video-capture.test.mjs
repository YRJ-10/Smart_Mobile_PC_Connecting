import assert from "node:assert/strict";
import test from "node:test";

import { ScreenVideoCapture } from "../renderer/media-worker/screen-video-capture.js";

test("screen capture is shared at native resolution and stops after its last session", async () => {
  const sourceVideo = new FakeTrack("video", "source-video");
  const sourceAudio = new FakeTrack("audio", "unexpected-audio");
  const stream = new FakeStream([sourceVideo, sourceAudio]);
  let displayRequests = 0;
  let requestedConstraints = null;
  const capture = new ScreenVideoCapture({
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
  assert.equal(requestedConstraints.audio, false);
  assert.equal(requestedConstraints.video.frameRate.ideal, 30);
  assert.equal(requestedConstraints.video.width, undefined);
  assert.equal(sourceAudio.stopped, true);
  assert.equal(sourceVideo.contentHint, "motion");
  assert.equal(first.contentHint, "motion");
  assert.equal(second.contentHint, "motion");
  assert.deepEqual(capture.state(), {
    active: true,
    sessions: 2,
    settings: { width: 1920, height: 1080, frameRate: 30 }
  });

  capture.release("session-1");
  assert.equal(first.stopped, true);
  assert.equal(sourceVideo.stopped, false);
  assert.equal(capture.state().sessions, 1);

  capture.release("session-2");
  assert.equal(second.stopped, true);
  assert.equal(sourceVideo.stopped, true);
  assert.equal(capture.state().active, false);
});

test("capture rejects a display stream without video", async () => {
  const audio = new FakeTrack("audio", "audio-only");
  const capture = new ScreenVideoCapture({
    getDisplayMedia: async () => new FakeStream([audio])
  });

  await assert.rejects(
    capture.acquire("session-1"),
    /did not provide a video track/
  );
  assert.equal(audio.stopped, true);
  assert.equal(capture.state().active, false);
});

test("unexpected source end reports affected sessions and releases clones", async () => {
  const sourceVideo = new FakeTrack("video", "source-video");
  const stream = new FakeStream([sourceVideo]);
  let affectedSessions = null;
  const capture = new ScreenVideoCapture({
    getDisplayMedia: async () => stream,
    onSourceEnded: (sessionIds) => {
      affectedSessions = sessionIds;
    }
  });

  const clone = await capture.acquire("session-1");
  sourceVideo.onended();

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
    return { width: 1920, height: 1080, frameRate: 30 };
  }
}
