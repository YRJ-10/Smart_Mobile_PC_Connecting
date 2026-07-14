import { spawn } from "node:child_process";
import { createServer } from "node:net";
import { join } from "node:path";
import { WORKER_DIR, saveConfig } from "./config.mjs";
import { workerInvocation } from "./python-runtime.mjs";

const CONTROL_PORT = 8080;

const ALLOWED_COMMANDS = new Set([
  "MOUSE_MOVE",
  "MOUSE_CLICK",
  "MOUSE_DRAG",
  "TYPE_TEXT",
  "SCROLL",
  "SPECIAL_KEY",
  "ZOOM",
  "MEDIA",
  "AUDIO_TOGGLE",
  "TOUCH_DOWN",
  "TOUCH_MOVE",
  "TOUCH_UP"
]);

const ALLOWED_SPECIAL_KEYS = new Set([
  "alttab",
  "enter",
  "left",
  "right",
  "up",
  "down",
  "backspace",
  "f5",
  "copy",
  "paste",
  "browserback",
  "browserforward"
]);

export class ControlServer {
  #config;
  #requestLog;
  #server = null;
  #worker = null;
  #clients = new Set();

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
      port: CONTROL_PORT,
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
      server.listen(CONTROL_PORT, this.#config.host ?? "0.0.0.0", () => {
        this.#requestLog.add("control_started", { port: CONTROL_PORT });
        resolveStart(this.state());
      });
    });
  }

  stop() {
    for (const socket of this.#clients) socket.destroy();
    this.#clients.clear();
    this.#stopWorker();

    if (!this.#server) return Promise.resolve(this.state());
    return new Promise((resolveStop, reject) => {
      const server = this.#server;
      server.close((error) => {
        if (error) {
          reject(error);
          return;
        }
        this.#server = null;
        this.#requestLog.add("control_stopped");
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
      buffer += chunk.toString("utf8");
      while (buffer.includes("\n")) {
        const index = buffer.indexOf("\n");
        const line = buffer.slice(0, index).trim();
        buffer = buffer.slice(index + 1);
        if (!line) continue;

        try {
          const message = JSON.parse(line);
          if (!authenticated) {
            authenticated = this.#authenticate(message, socket);
            continue;
          }
          this.#handleCommand(message, socket);
        } catch (error) {
          this.#send(socket, { ok: false, error: error.message });
        }
      }
    });

    socket.on("close", () => this.#clients.delete(socket));
    socket.on("error", () => this.#clients.delete(socket));
  }

  #authenticate(message, socket) {
    if (message.type !== "auth") {
      this.#send(socket, { ok: false, error: "Auth required" });
      socket.destroy();
      return false;
    }

    const deviceId = String(message.device_id ?? "").trim();
    const deviceToken = String(message.device_token ?? "").trim();
    const trustedDevice = this.#config.trusted_devices?.[deviceId];
    if (!trustedDevice || trustedDevice.token !== deviceToken) {
      this.#requestLog.add("control_unauthorized");
      this.#send(socket, { ok: false, error: "Unauthorized" });
      socket.destroy();
      return false;
    }

    trustedDevice.last_seen_at = new Date().toISOString();
    saveConfig(this.#config);
    this.#requestLog.add("control_client_connected", { device: trustedDevice.name ?? deviceId });
    this.#send(socket, { ok: true, event: "control_ready" });
    return true;
  }

  #handleCommand(command, socket) {
    const normalized = normalizeCommand(command, socket);
    validateCommand(normalized);
    this.#sendToWorker(normalized);
    this.#requestLog.add("remote_command", { command: normalized.type });
    this.#send(socket, { ok: true, event: "command_accepted", command: normalized.type });
  }

  #sendToWorker(command) {
    const worker = this.#ensureWorker();
    worker.stdin.write(`${JSON.stringify(command)}\n`);
  }

  #ensureWorker() {
    if (this.#worker && !this.#worker.killed) return this.#worker;

    const workerPath = join(WORKER_DIR, "worker.py");
    const worker = workerInvocation(workerPath, "smart-mpc-worker.exe");
    this.#worker = spawn(worker.command, worker.args, {
      windowsHide: true,
      stdio: ["pipe", "pipe", "pipe"]
    });
    this.#worker.stdout.on("data", (chunk) => {
      for (const line of chunk.toString("utf8").split(/\r?\n/)) {
        if (line.trim()) this.#requestLog.add("worker_event", { detail: line.trim().slice(0, 160) });
      }
    });
    this.#worker.stderr.on("data", (chunk) => {
      this.#requestLog.add("worker_error", { error: chunk.toString("utf8").trim().slice(0, 160) });
    });
    this.#worker.on("exit", (code) => {
      this.#requestLog.add("worker_exit", { code });
      this.#worker = null;
    });
    return this.#worker;
  }

  #stopWorker() {
    if (!this.#worker) return;
    this.#worker.kill();
    this.#worker = null;
  }

  #send(socket, payload) {
    socket.write(`${JSON.stringify(payload)}\n`);
  }
}

function normalizeCommand(command, socket) {
  const type = String(command.type ?? "").trim();
  if (type === "TYPE_TEXT") {
    return { ...command, text: String(command.text ?? "").slice(0, 1000) };
  }
  if (type === "AUDIO_TOGGLE") {
    return {
      ...command,
      type,
      enabled: Boolean(command.enabled),
      port: Number(command.port ?? 0),
      target_host: String(command.target_host ?? clientHost(socket)).trim()
    };
  }
  return { ...command, type };
}

function validateCommand(command) {
  if (!ALLOWED_COMMANDS.has(command.type)) {
    throw new Error(`Unsupported command type: ${command.type}`);
  }

  if (command.type === "SPECIAL_KEY" && !ALLOWED_SPECIAL_KEYS.has(String(command.key ?? ""))) {
    throw new Error(`Unsupported special key: ${command.key}`);
  }

  if (command.type === "MOUSE_CLICK" && !["left", "right", "middle"].includes(String(command.button ?? "left"))) {
    throw new Error(`Unsupported mouse button: ${command.button}`);
  }

  if (command.type === "MOUSE_DRAG" && !["down", "up"].includes(String(command.action ?? ""))) {
    throw new Error(`Unsupported drag action: ${command.action}`);
  }

  if (command.type === "AUDIO_TOGGLE" && command.enabled) {
    if (!command.target_host) throw new Error("Missing audio target host");
    if (!Number.isInteger(command.port) || command.port < 1024 || command.port > 65535) {
      throw new Error(`Invalid audio port: ${command.port}`);
    }
  }
}

function clientHost(socket) {
  const value = String(socket.remoteAddress ?? "").trim();
  if (value.startsWith("::ffff:")) return value.slice(7);
  if (value === "::1") return "127.0.0.1";
  return value;
}
