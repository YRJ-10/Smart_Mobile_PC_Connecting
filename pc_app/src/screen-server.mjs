import { spawn } from "node:child_process";
import { createServer } from "node:net";
import { join } from "node:path";
import { WORKER_DIR, saveConfig } from "./config.mjs";
import { workerInvocation } from "./python-runtime.mjs";

const SCREEN_PORT = 8082;

export class ScreenServer {
  #config;
  #requestLog;
  #server = null;
  #clients = new Set();
  #streams = new Map();

  constructor({ config, requestLog }) {
    this.#config = config;
    this.#requestLog = requestLog;
  }

  get running() {
    return Boolean(this.#server);
  }

  state() {
    return {
      running: this.running,
      port: SCREEN_PORT,
      clients: this.#clients.size
    };
  }

  start() {
    if (this.#server) return Promise.resolve(this.state());

    this.#server = createServer((socket) => this.#handleSocket(socket));
    return new Promise((resolveStart, reject) => {
      const server = this.#server;
      server.once("error", (error) => {
        this.#server = null;
        reject(error);
      });
      server.listen(SCREEN_PORT, this.#config.host ?? "0.0.0.0", () => {
        this.#requestLog.add("screen_started", { port: SCREEN_PORT });
        resolveStart(this.state());
      });
    });
  }

  stop() {
    for (const socket of this.#clients) socket.destroy();
    this.#clients.clear();
    for (const stream of this.#streams.values()) stream.kill();
    this.#streams.clear();

    if (!this.#server) return Promise.resolve(this.state());
    return new Promise((resolveStop, reject) => {
      const server = this.#server;
      server.close((error) => {
        if (error) {
          reject(error);
          return;
        }
        this.#server = null;
        this.#requestLog.add("screen_stopped");
        resolveStop(this.state());
      });
    });
  }

  #handleSocket(socket) {
    socket.setNoDelay(true);
    this.#clients.add(socket);

    let authenticated = false;
    let buffer = "";

    socket.on("data", (chunk) => {
      if (authenticated) return;

      buffer += chunk.toString("utf8");
      const index = buffer.indexOf("\n");
      if (index < 0) return;

      const line = buffer.slice(0, index).trim();
      try {
        const message = JSON.parse(line);
        authenticated = this.#authenticate(message, socket);
        if (authenticated) this.#startStream(socket);
      } catch (error) {
        this.#sendLine(socket, { ok: false, error: error.message });
        socket.destroy();
      }
    });

    socket.on("close", () => this.#cleanupSocket(socket));
    socket.on("error", () => this.#cleanupSocket(socket));
  }

  #authenticate(message, socket) {
    if (message.type !== "auth") {
      this.#sendLine(socket, { ok: false, error: "Auth required" });
      socket.destroy();
      return false;
    }

    const deviceId = String(message.device_id ?? "").trim();
    const deviceToken = String(message.device_token ?? "").trim();
    const trustedDevice = this.#config.trusted_devices?.[deviceId];
    if (!trustedDevice || trustedDevice.token !== deviceToken) {
      this.#requestLog.add("screen_unauthorized");
      this.#sendLine(socket, { ok: false, error: "Unauthorized" });
      socket.destroy();
      return false;
    }

    trustedDevice.last_seen_at = new Date().toISOString();
    saveConfig(this.#config);
    this.#requestLog.add("screen_client_connected", { device: trustedDevice.name ?? deviceId });
    this.#sendLine(socket, { ok: true, event: "screen_ready", encoding: "jpeg" });
    return true;
  }

  #startStream(socket) {
    const workerPath = join(WORKER_DIR, "screen_streamer.py");
    const worker = workerInvocation(workerPath, "smart-mpc-screen-streamer.exe");
    const stream = spawn(worker.command, worker.args, {
      windowsHide: true,
      stdio: ["ignore", "pipe", "pipe"]
    });

    this.#streams.set(socket, stream);
    let pending = Buffer.alloc(0);
    let latestFrame = null;
    let sending = false;

    const sendLatest = () => {
      if (sending || socket.destroyed || !latestFrame) return;

      const frame = latestFrame;
      latestFrame = null;
      const header = Buffer.allocUnsafe(4);
      header.writeUInt32BE(frame.length, 0);
      sending = true;

      const finish = () => {
        sending = false;
        sendLatest();
      };

      if (socket.write(Buffer.concat([header, frame]))) {
        setImmediate(finish);
      } else {
        socket.once("drain", finish);
      }
    };

    stream.stdout.on("data", (chunk) => {
      if (socket.destroyed) return;

      pending = Buffer.concat([pending, chunk]);
      while (pending.length >= 4) {
        const length = pending.readUInt32BE(0);
        if (length <= 0 || length > 20 * 1024 * 1024) {
          this.#requestLog.add("screen_frame_error", { error: `invalid length ${length}` });
          socket.destroy();
          stream.kill();
          return;
        }
        if (pending.length < length + 4) break;
        latestFrame = pending.subarray(4, length + 4);
        pending = pending.subarray(length + 4);
      }

      sendLatest();
    });
    stream.stderr.on("data", (chunk) => {
      this.#requestLog.add("screen_worker_error", { error: chunk.toString("utf8").trim().slice(0, 160) });
    });
    stream.on("exit", (code) => {
      this.#requestLog.add("screen_worker_exit", { code });
      this.#streams.delete(socket);
      if (!socket.destroyed) socket.destroy();
    });
  }

  #cleanupSocket(socket) {
    this.#clients.delete(socket);
    const stream = this.#streams.get(socket);
    if (stream) stream.kill();
    this.#streams.delete(socket);
  }

  #sendLine(socket, payload) {
    socket.write(`${JSON.stringify(payload)}\n`);
  }
}
