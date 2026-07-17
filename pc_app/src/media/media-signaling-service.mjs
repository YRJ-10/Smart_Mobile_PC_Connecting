import { randomUUID } from "node:crypto";
import { EventEmitter } from "node:events";

const MAX_QUEUED_SIGNALS = 256;
const MAX_WAIT_MS = 25_000;
const SESSION_IDLE_TIMEOUT_MS = 120_000;
const CLIENT_SIGNAL_KINDS = new Set(["offer", "ice-candidate", "ice-complete"]);
const SERVER_SIGNAL_KINDS = new Set(["offer", "answer", "ice-candidate", "ice-complete", "error"]);

export class MediaSignalingError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.name = "MediaSignalingError";
    this.status = status;
  }
}

export class MediaSignalingService extends EventEmitter {
  #requestLog;
  #sessions = new Map();
  #workerReady = false;

  constructor({ requestLog } = {}) {
    super();
    this.#requestLog = requestLog;
  }

  state() {
    this.#sweepExpired();
    return {
      active_sessions: this.#sessions.size,
      worker_ready: this.#workerReady
    };
  }

  capabilities() {
    return {
      protocol_version: 1,
      local_only: true,
      signaling: "http-long-poll",
      ice_servers: [],
      engines: {
        legacy: { available: true },
        webrtc: {
          signaling_available: true,
          media_available: this.#workerReady,
          audio: { codecs: ["opus"], sample_rate: 48000 },
          video: { codecs: ["H264", "VP8"] }
        }
      }
    };
  }

  setWorkerReady(ready) {
    this.#workerReady = Boolean(ready);
  }

  createSession(deviceId, request = {}) {
    this.#sweepExpired();
    if (!this.#workerReady) {
      throw new MediaSignalingError("WebRTC media worker is unavailable", 503);
    }
    const owner = requiredText(deviceId, "device_id", 256);
    const engine = String(request.engine ?? "webrtc").trim().toLowerCase();
    if (engine !== "webrtc") throw new MediaSignalingError("Unsupported media engine");

    const tracks = {
      audio: Boolean(request.tracks?.audio),
      video: Boolean(request.tracks?.video)
    };
    if (!tracks.audio && !tracks.video) {
      throw new MediaSignalingError("At least one media track is required");
    }

    this.stopDeviceSessions(owner, "replaced");
    const now = Date.now();
    const session = {
      id: randomUUID(),
      device_id: owner,
      engine,
      tracks,
      state: "negotiating",
      created_at_ms: now,
      last_seen_at_ms: now,
      client_sequence: 0,
      server_sequence: 0,
      client_signals: [],
      server_signals: [],
      waiters: new Set()
    };
    this.#sessions.set(session.id, session);
    const summary = publicSession(session);
    this.#requestLog?.add("media_session_started", {
      device: owner,
      audio: tracks.audio,
      video: tracks.video
    });
    this.emit("session-started", { ...summary, device_id: owner });
    return summary;
  }

  setSessionState(sessionId, state) {
    const session = this.#session(sessionId);
    const next = String(state ?? "").trim().toLowerCase();
    if (!["negotiating", "connected", "disconnected", "failed", "closed"].includes(next)) {
      throw new MediaSignalingError("Unsupported media session state");
    }
    session.state = next;
    this.#touch(session);
    return publicSession(session);
  }

  status(deviceId, sessionId) {
    return publicSession(this.#ownedSession(deviceId, sessionId));
  }

  enqueueClientSignal(deviceId, sessionId, signal) {
    const session = this.#ownedSession(deviceId, sessionId);
    const normalized = normalizeSignal(signal, CLIENT_SIGNAL_KINDS);
    const entry = {
      sequence: ++session.client_sequence,
      created_at_ms: Date.now(),
      ...normalized
    };
    session.client_signals.push(entry);
    trimQueue(session.client_signals);
    this.#touch(session);
    this.emit("client-signal", { session_id: session.id, signal: entry });
    return entry;
  }

  takeClientSignals(sessionId, after = 0) {
    const session = this.#session(sessionId);
    return queuedAfter(session.client_signals, after);
  }

  publishServerSignal(sessionId, signal) {
    const session = this.#session(sessionId);
    const normalized = normalizeSignal(signal, SERVER_SIGNAL_KINDS);
    const entry = {
      sequence: ++session.server_sequence,
      created_at_ms: Date.now(),
      ...normalized
    };
    session.server_signals.push(entry);
    trimQueue(session.server_signals);
    this.#touch(session);
    this.#flushWaiters(session);
    return entry;
  }

  async readServerSignals(deviceId, sessionId, { after = 0, waitMs = 0 } = {}) {
    const session = this.#ownedSession(deviceId, sessionId);
    const sequence = nonNegativeInteger(after, "after");
    const timeout = Math.min(nonNegativeInteger(waitMs, "wait_ms"), MAX_WAIT_MS);
    const available = queuedAfter(session.server_signals, sequence);
    if (available.length || timeout === 0) {
      this.#touch(session);
      return { signals: available, stopped: false };
    }

    return new Promise((resolve) => {
      const waiter = {
        after: sequence,
        resolve,
        timer: null
      };
      waiter.timer = setTimeout(() => {
        session.waiters.delete(waiter);
        this.#touch(session);
        resolve({ signals: [], stopped: false });
      }, timeout);
      waiter.timer.unref?.();
      session.waiters.add(waiter);
    });
  }

  stopSession(deviceId, sessionId, reason = "client_requested") {
    const session = this.#ownedSession(deviceId, sessionId);
    this.#stop(session, reason);
    return true;
  }

  stopDeviceSessions(deviceId, reason = "device_revoked") {
    const owner = String(deviceId ?? "").trim();
    for (const session of [...this.#sessions.values()]) {
      if (session.device_id === owner) this.#stop(session, reason);
    }
  }

  reset(reason = "server_stopped") {
    for (const session of [...this.#sessions.values()]) this.#stop(session, reason);
  }

  #ownedSession(deviceId, sessionId) {
    const session = this.#session(sessionId);
    if (session.device_id !== String(deviceId ?? "").trim()) {
      throw new MediaSignalingError("Media session not found", 404);
    }
    return session;
  }

  #session(sessionId) {
    this.#sweepExpired();
    const id = String(sessionId ?? "").trim();
    const session = this.#sessions.get(id);
    if (!session) throw new MediaSignalingError("Media session not found", 404);
    return session;
  }

  #touch(session) {
    session.last_seen_at_ms = Date.now();
  }

  #flushWaiters(session) {
    for (const waiter of [...session.waiters]) {
      const available = queuedAfter(session.server_signals, waiter.after);
      if (!available.length) continue;
      clearTimeout(waiter.timer);
      session.waiters.delete(waiter);
      waiter.resolve({ signals: available, stopped: false });
    }
  }

  #stop(session, reason) {
    if (!this.#sessions.delete(session.id)) return;
    session.state = "stopped";
    for (const waiter of session.waiters) {
      clearTimeout(waiter.timer);
      waiter.resolve({ signals: [], stopped: true, reason });
    }
    session.waiters.clear();
    const summary = publicSession(session);
    this.#requestLog?.add("media_session_stopped", { device: session.device_id, reason });
    this.emit("session-stopped", { ...summary, device_id: session.device_id, reason });
  }

  #sweepExpired() {
    const cutoff = Date.now() - SESSION_IDLE_TIMEOUT_MS;
    for (const session of [...this.#sessions.values()]) {
      if (session.last_seen_at_ms < cutoff) this.#stop(session, "idle_timeout");
    }
  }
}

function publicSession(session) {
  return {
    session_id: session.id,
    engine: session.engine,
    tracks: { ...session.tracks },
    state: session.state,
    created_at_ms: session.created_at_ms,
    last_seen_at_ms: session.last_seen_at_ms
  };
}

function normalizeSignal(signal, allowedKinds) {
  if (!signal || typeof signal !== "object" || Array.isArray(signal)) {
    throw new MediaSignalingError("Signal must be an object");
  }
  const kind = String(signal.kind ?? "").trim().toLowerCase();
  if (!allowedKinds.has(kind)) throw new MediaSignalingError("Unsupported signal kind");

  if (kind === "offer" || kind === "answer") {
    return { kind, sdp: requiredText(signal.sdp, "sdp", 1024 * 1024) };
  }
  if (kind === "ice-candidate") {
    return {
      kind,
      candidate: requiredText(signal.candidate, "candidate", 8192),
      sdp_mid: optionalText(signal.sdp_mid, 128),
      sdp_mline_index: nonNegativeInteger(signal.sdp_mline_index ?? 0, "sdp_mline_index")
    };
  }
  if (kind === "error") {
    return { kind, message: requiredText(signal.message, "message", 2048) };
  }
  return { kind };
}

function queuedAfter(queue, after) {
  const sequence = Number(after) || 0;
  return queue.filter((entry) => entry.sequence > sequence).map((entry) => ({ ...entry }));
}

function trimQueue(queue) {
  if (queue.length > MAX_QUEUED_SIGNALS) queue.splice(0, queue.length - MAX_QUEUED_SIGNALS);
}

function requiredText(value, name, maxLength) {
  const text = String(value ?? "").trim();
  if (!text) throw new MediaSignalingError(`Missing ${name}`);
  if (text.length > maxLength) throw new MediaSignalingError(`${name} is too large`, 413);
  return text;
}

function optionalText(value, maxLength) {
  if (value == null) return null;
  const text = String(value);
  if (text.length > maxLength) throw new MediaSignalingError("Signal field is too large", 413);
  return text;
}

function nonNegativeInteger(value, name) {
  const number = Number(value);
  if (!Number.isInteger(number) || number < 0) {
    throw new MediaSignalingError(`${name} must be a non-negative integer`);
  }
  return number;
}
