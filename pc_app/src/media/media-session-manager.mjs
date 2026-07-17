export class MediaSessionManager {
  #signaling;
  #worker;
  #requestLog;
  #sessionStarts = new Map();

  constructor({ signaling, worker = null, requestLog } = {}) {
    this.#signaling = signaling;
    this.#worker = worker;
    this.#requestLog = requestLog;
    signaling.setWorkerReady(Boolean(worker?.available));
    signaling.on("session-started", this.#onSessionStarted);
    signaling.on("client-signal", this.#onClientSignal);
    signaling.on("session-stopped", this.#onSessionStopped);
    worker?.on("server-signal", this.#onServerSignal);
    worker?.on("session-state", this.#onWorkerSessionState);
    worker?.on("worker-error", this.#onWorkerError);
    worker?.on("unexpected-exit", this.#onUnexpectedExit);
  }

  state() {
    return this.#worker?.state() ?? {
      available: false,
      running: false,
      sessions: 0
    };
  }

  async stopAll() {
    this.#signaling.reset();
    await this.#worker?.stop();
    this.#sessionStarts.clear();
  }

  #onSessionStarted = (session) => {
    if (!this.#worker) return;
    const start = this.#worker.openSession(session);
    this.#sessionStarts.set(session.session_id, start);
    start.catch((error) => {
      this.#handleSessionFailure(session.session_id, error);
    });
  };

  #onClientSignal = ({ session_id: sessionId, signal }) => {
    if (!this.#worker) return;
    const start = this.#sessionStarts.get(sessionId) ?? Promise.resolve();
    start
      .then(() => this.#worker.sendSignal(sessionId, signal))
      .catch((error) => this.#handleSessionFailure(sessionId, error));
  };

  #onSessionStopped = ({ session_id: sessionId }) => {
    if (!this.#worker) return;
    const start = this.#sessionStarts.get(sessionId) ?? Promise.resolve();
    this.#sessionStarts.delete(sessionId);
    start
      .catch(() => {})
      .then(() => this.#worker.closeSession(sessionId))
      .catch((error) => {
        this.#requestLog?.add("media_worker_error", { error: error.message });
      });
  };

  #onServerSignal = ({ session_id: sessionId, signal }) => {
    try {
      this.#signaling.publishServerSignal(sessionId, signal);
    } catch (error) {
      this.#requestLog?.add("media_signal_error", { error: error.message });
    }
  };

  #onWorkerSessionState = ({ session_id: sessionId, state }) => {
    try {
      this.#signaling.setSessionState(sessionId, normalizePeerState(state));
    } catch (error) {
      this.#requestLog?.add("media_state_error", { error: error.message });
    }
  };

  #onWorkerError = ({ session_id: sessionId, error }) => {
    this.#handleSessionFailure(sessionId, new Error(error));
  };

  #onUnexpectedExit = ({ session_ids: sessionIds }) => {
    for (const sessionId of sessionIds) {
      this.#handleSessionFailure(sessionId, new Error("Media worker exited unexpectedly"));
    }
  };

  #handleSessionFailure(sessionId, error) {
    this.#requestLog?.add("media_worker_error", {
      session: sessionId,
      error: error.message
    });
    try {
      this.#signaling.setSessionState(sessionId, "failed");
      this.#signaling.publishServerSignal(sessionId, {
        kind: "error",
        message: error.message
      });
    } catch {
      // The session may already have been stopped by the client.
    }
  }
}

function normalizePeerState(state) {
  if (state === "connected") return "connected";
  if (state === "connecting" || state === "new") return "negotiating";
  if (state === "failed" || state === "disconnected" || state === "closed") return state;
  return "negotiating";
}
