import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import test from "node:test";

import { MediaSessionManager } from "../src/media/media-session-manager.mjs";
import {
  MediaSignalingError,
  MediaSignalingService
} from "../src/media/media-signaling-service.mjs";

test("session manager starts worker lazily, forwards signals, and stops after last session", async () => {
  const signaling = new MediaSignalingService();
  const worker = new FakeWorker();
  const manager = new MediaSessionManager({ signaling, worker });

  assert.equal(manager.state().running, false);
  const session = signaling.createSession("phone-1", {
    tracks: { audio: true }
  });
  await nextTurn();
  assert.equal(worker.opened.length, 1);
  assert.equal(manager.state().running, true);

  signaling.enqueueClientSignal("phone-1", session.session_id, {
    kind: "offer",
    sdp: "v=0"
  });
  await nextTurn();
  assert.equal(worker.signals.length, 1);
  assert.equal(worker.signals[0].signal.kind, "offer");

  signaling.stopSession("phone-1", session.session_id);
  await nextTurn();
  assert.equal(worker.closed.length, 1);
  assert.equal(manager.state().running, false);
});

test("server signaling is rejected when no Electron media worker is available", () => {
  const signaling = new MediaSignalingService();
  new MediaSessionManager({ signaling });

  assert.throws(
    () => signaling.createSession("phone-1", { tracks: { video: true } }),
    (error) => error instanceof MediaSignalingError && error.status === 503
  );
});

class FakeWorker extends EventEmitter {
  available = true;
  running = false;
  sessions = new Set();
  opened = [];
  closed = [];
  signals = [];

  state() {
    return {
      available: true,
      running: this.running,
      sessions: this.sessions.size
    };
  }

  async openSession(session) {
    this.running = true;
    this.sessions.add(session.session_id);
    this.opened.push(session.session_id);
  }

  async sendSignal(sessionId, signal) {
    this.signals.push({ sessionId, signal });
  }

  async closeSession(sessionId) {
    this.sessions.delete(sessionId);
    this.closed.push(sessionId);
    if (this.sessions.size === 0) this.running = false;
  }

  async stop() {
    this.sessions.clear();
    this.running = false;
  }
}

function nextTurn() {
  return new Promise((resolve) => setImmediate(resolve));
}
