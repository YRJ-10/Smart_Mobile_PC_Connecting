import { EventEmitter } from "node:events";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";
import { fileURLToPath } from "node:url";
import { BrowserWindow, desktopCapturer, ipcMain, session } from "electron";

const MODULE_DIR = dirname(fileURLToPath(import.meta.url));
const MEDIA_RENDERER_DIR = join(MODULE_DIR, "..", "..", "renderer", "media-worker");
const READY_TIMEOUT_MS = 5_000;
const STOP_TIMEOUT_MS = 1_500;

export class MediaWorkerProcess extends EventEmitter {
  #window = null;
  #sessions = new Set();
  #readyPromise = null;
  #resolveReady = null;
  #rejectReady = null;
  #stopTask = null;
  #resolveStopped = null;
  #stopping = false;
  #ipcAttached = false;
  #electronSession = null;
  #audioCaptureState = { active: false, sessions: 0, settings: null };

  get available() {
    return true;
  }

  get running() {
    return Boolean(this.#window && !this.#window.isDestroyed());
  }

  state() {
    return {
      available: this.available,
      running: this.running,
      sessions: this.#sessions.size,
      audio: { ...this.#audioCaptureState }
    };
  }

  async openSession(session) {
    const sessionId = String(session.session_id ?? "");
    if (!sessionId) throw new Error("Missing media session id");
    await this.start();
    if (this.#sessions.has(sessionId)) return;
    this.#sessions.add(sessionId);
    this.#send({ type: "session-open", session });
  }

  async sendSignal(sessionId, signal) {
    if (!this.#sessions.has(sessionId)) throw new Error("Media session is not running");
    this.#send({ type: "signal", session_id: sessionId, signal });
  }

  async closeSession(sessionId) {
    if (!this.#sessions.delete(sessionId)) return;
    if (this.running) this.#send({ type: "session-close", session_id: sessionId });
    if (this.#sessions.size === 0) await this.stop();
  }

  async start() {
    if (this.#readyPromise) return this.#readyPromise;
    if (this.running) return;

    this.#attachIpc();
    const workerSession = this.#ensureElectronSession();
    this.#readyPromise = new Promise((resolve, reject) => {
      this.#resolveReady = resolve;
      this.#rejectReady = reject;
    });
    const preload = join(MEDIA_RENDERER_DIR, "preload.cjs");
    const window = new BrowserWindow({
      show: false,
      webPreferences: {
        preload,
        contextIsolation: true,
        sandbox: true,
        backgroundThrottling: false,
        session: workerSession
      }
    });
    this.#window = window;
    window.on("closed", () => this.#handleClosed(window));
    window.webContents.once("render-process-gone", () => {
      if (this.#window === window && this.running) window.destroy();
    });
    try {
      await window.loadFile(join(MEDIA_RENDERER_DIR, "index.html"));
      await withTimeout(this.#readyPromise, READY_TIMEOUT_MS, "Media worker startup");
      this.emit("started", this.state());
    } catch (error) {
      if (this.#window === window) {
        if (this.running) window.destroy();
        this.#cleanupState();
      }
      throw error;
    }
  }

  async stop() {
    if (!this.running) {
      this.#cleanupState();
      return;
    }
    if (this.#stopTask) return this.#stopTask;

    this.#stopping = true;
    this.#stopTask = this.#stopWindow(this.#window);
    return this.#stopTask;
  }

  async #stopWindow(window) {
    const stopped = new Promise((resolve) => {
      const timeout = setTimeout(resolve, STOP_TIMEOUT_MS);
      this.#resolveStopped = () => {
        clearTimeout(timeout);
        resolve();
      };
    });
    this.#send({ type: "shutdown" });
    await stopped;
    if (this.#window === window && !window.isDestroyed()) {
      const closed = new Promise((resolve) => window.once("closed", resolve));
      window.destroy();
      await closed;
    }
    if (this.#window === window) this.#cleanupState();
    this.emit("stopped", this.state());
  }

  #send(command) {
    if (!this.running) throw new Error("Media worker is not running");
    this.#window.webContents.send("smart-mpc-media:command", command);
  }

  #attachIpc() {
    if (this.#ipcAttached) return;
    ipcMain.on("smart-mpc-media:ready", this.#onReady);
    ipcMain.on("smart-mpc-media:event", this.#onEvent);
    this.#ipcAttached = true;
  }

  #ensureElectronSession() {
    if (this.#electronSession) return this.#electronSession;
    const workerSession = session.fromPartition("smart-mpc-media-worker");
    const allowedUrl = pathToFileURL(join(MEDIA_RENDERER_DIR, "index.html")).href;
    workerSession.setDisplayMediaRequestHandler(async (request, callback) => {
      if (!request.audioRequested || request.frame?.url !== allowedUrl) {
        callback({});
        return;
      }
      try {
        const sources = await desktopCapturer.getSources({
          types: ["screen"],
          thumbnailSize: { width: 0, height: 0 }
        });
        if (!sources.length) {
          callback({});
          return;
        }
        callback({ video: sources[0], audio: "loopback" });
      } catch {
        callback({});
      }
    });
    this.#electronSession = workerSession;
    return workerSession;
  }

  #detachIpc() {
    if (!this.#ipcAttached) return;
    ipcMain.removeListener("smart-mpc-media:ready", this.#onReady);
    ipcMain.removeListener("smart-mpc-media:event", this.#onEvent);
    this.#ipcAttached = false;
  }

  #onReady = (event) => {
    if (event.sender !== this.#window?.webContents) return;
    this.#resolveReady?.();
    this.#resolveReady = null;
    this.#rejectReady = null;
  };

  #onEvent = (event, payload) => {
    if (event.sender !== this.#window?.webContents || !payload) return;
    if (payload.type === "worker-stopped") {
      this.#resolveStopped?.();
      this.#resolveStopped = null;
      return;
    }
    if (payload.type === "server-signal") {
      this.emit("server-signal", payload);
      return;
    }
    if (payload.type === "session-state") {
      this.emit("session-state", payload);
      return;
    }
    if (payload.type === "audio-capture-state") {
      this.#audioCaptureState = {
        active: Boolean(payload.state?.active),
        sessions: Number(payload.state?.sessions ?? 0),
        settings: payload.state?.settings ?? null
      };
      this.emit("audio-capture-state", this.state());
      return;
    }
    if (payload.type === "worker-error") {
      this.emit("worker-error", payload);
    }
  };

  #handleClosed(window) {
    if (this.#window !== window) return;
    const unexpected = !this.#stopping && this.#sessions.size > 0;
    const affectedSessions = [...this.#sessions];
    this.#rejectReady?.(new Error("Media worker closed during startup"));
    this.#cleanupState();
    if (unexpected) this.emit("unexpected-exit", { session_ids: affectedSessions });
  }

  #cleanupState() {
    this.#detachIpc();
    this.#window = null;
    this.#sessions.clear();
    this.#readyPromise = null;
    this.#resolveReady = null;
    this.#rejectReady = null;
    this.#stopTask = null;
    this.#resolveStopped = null;
    this.#stopping = false;
    this.#audioCaptureState = { active: false, sessions: 0, settings: null };
  }
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
