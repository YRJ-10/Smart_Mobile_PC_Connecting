import { createServer, request } from "node:http";
import { randomUUID } from "node:crypto";
import { execFile, spawn } from "node:child_process";
import {
  copyFileSync,
  existsSync,
  readFileSync,
  readdirSync,
  statSync,
  writeFileSync
} from "node:fs";
import { homedir, hostname, platform } from "node:os";
import { join, parse, relative, resolve } from "node:path";
import {
  APP_NAME,
  DEFAULT_PORT,
  HEADER_DEVICE_ID,
  HEADER_DEVICE_TOKEN,
  HEADER_SESSION_TOKEN,
  HEADER_PAIRING_TOKEN,
  MAX_BODY_BYTES
} from "./constants.mjs";
import { baseUrls, localIps } from "./network.mjs";
import { createDeviceToken, loadOrCreateConfig, saveConfig } from "./config.mjs";
import { ControlServer } from "./control-server.mjs";
import { DiscoveryServer } from "./discovery-server.mjs";
import { ScreenServer } from "./screen-server.mjs";
import { RequestLog } from "./request-log.mjs";

function safeFilename(name) {
  const cleaned = String(name ?? "")
    .split("")
    .filter((ch) => /[a-zA-Z0-9 ._\-()[\]]/.test(ch))
    .join("")
    .trim();
  return cleaned || `file-${Date.now()}`;
}

function uniquePath(directory, filename) {
  const clean = safeFilename(filename);
  const parsed = parse(clean);
  let target = resolve(directory, clean);
  let index = 1;

  while (existsSync(target)) {
    target = resolve(directory, `${parsed.name}-${index}${parsed.ext}`);
    index += 1;
  }

  return target;
}

function safeChildPath(directory, filename) {
  const target = resolve(directory, safeFilename(filename));
  const distance = relative(resolve(directory), target);
  if (distance.startsWith("..") || distance === "" || resolve(distance) === distance) {
    throw new Error("Invalid filename");
  }
  return target;
}

function listFiles(directory) {
  if (!existsSync(directory)) return [];
  return readdirSync(directory, { withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => {
      const target = join(directory, entry.name);
      const stats = statSync(target);
      return {
        name: entry.name,
        bytes: stats.size,
        modified_at: stats.mtime.toISOString()
      };
    })
    .sort((a, b) => b.modified_at.localeCompare(a.modified_at));
}

function run(command, args, options = {}) {
  return new Promise((resolveRun, reject) => {
    const child = execFile(command, args, { windowsHide: true, ...options }, (error) => {
      if (error) reject(error);
      else resolveRun();
    });
    child.stdin?.end();
  });
}

function runCapture(command, args, options = {}) {
  return new Promise((resolveRun, reject) => {
    execFile(command, args, { windowsHide: true, ...options }, (error, stdout) => {
      if (error) reject(error);
      else resolveRun(stdout);
    });
  });
}

function postLocalJson(url, timeoutMs = 5000) {
  return new Promise((resolvePost, reject) => {
    const req = request(url, { method: "POST", timeout: timeoutMs }, (res) => {
      let body = "";
      res.setEncoding("utf8");
      res.on("data", (chunk) => {
        body += chunk;
        if (body.length > 1024 * 1024) req.destroy(new Error("Local API response is too large"));
      });
      res.on("end", () => {
        let json = {};
        try {
          json = body ? JSON.parse(body) : {};
        } catch {
          reject(new Error("Local API returned invalid JSON"));
          return;
        }

        if (res.statusCode < 200 || res.statusCode >= 300) {
          reject(new Error(json.error || `Local API failed with HTTP ${res.statusCode}`));
          return;
        }

        resolvePost(json);
      });
    });
    req.on("timeout", () => req.destroy(new Error("Local API timed out")));
    req.on("error", reject);
    req.end();
  });
}

async function switchMonitorProfile(profile) {
  const profileId = String(profile ?? "").trim();
  if (!/^[1-6]$/.test(profileId)) throw new Error("Invalid monitor profile");

  const result = await postLocalJson(`http://127.0.0.1:47777/profile/${profileId}`);
  if (result.ok === false) throw new Error(result.error || "Monitor switcher rejected the profile");
  return result;
}

async function openTarget(target) {
  const value = String(target ?? "").trim();
  if (!value) throw new Error("Missing target");

  if (platform() === "win32") {
    await run("cmd", ["/c", "start", "", value]);
    return;
  }

  await run("xdg-open", [value]);
}

async function setClipboard(text) {
  if (platform() !== "win32") throw new Error("Clipboard is only implemented for Windows in this phase");

  await new Promise((resolveRun, reject) => {
    const child = spawn("powershell.exe", ["-NoProfile", "-Command", "Set-Clipboard -Value $input"], {
      windowsHide: true,
      stdio: ["pipe", "ignore", "pipe"]
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) resolveRun();
      else reject(new Error(`Set-Clipboard exited with code ${code}`));
    });
    child.stdin.end(String(text ?? ""));
  });
}

async function getClipboard() {
  if (platform() !== "win32") throw new Error("Clipboard is only implemented for Windows in this phase");
  return runCapture("powershell.exe", ["-NoProfile", "-Command", "Get-Clipboard -Raw"]);
}

async function lockPc() {
  if (platform() !== "win32") throw new Error("Lock PC is only implemented for Windows");
  await run("rundll32.exe", ["user32.dll,LockWorkStation"]);
}

async function sleepPc() {
  if (platform() !== "win32") throw new Error("Sleep PC is only implemented for Windows");
  await run("powershell.exe", [
    "-NoProfile",
    "-Command",
    "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Application]::SetSuspendState('Suspend', $false, $false)"
  ]);
}

async function openChrome(config = {}) {
  if (platform() !== "win32") throw new Error("Open Chrome is only implemented for Windows");

  const candidates = [
    process.env.PROGRAMFILES ? join(process.env.PROGRAMFILES, "Google", "Chrome", "Application", "chrome.exe") : "",
    process.env["PROGRAMFILES(X86)"] ? join(process.env["PROGRAMFILES(X86)"], "Google", "Chrome", "Application", "chrome.exe") : "",
    process.env.LOCALAPPDATA ? join(process.env.LOCALAPPDATA, "Google", "Chrome", "Application", "chrome.exe") : ""
  ].filter(Boolean);
  const chromePath = candidates.find((candidate) => existsSync(candidate));
  const args = chromeArgs(config);
  if (chromePath) {
    await run(chromePath, args);
    return;
  }

  await run("cmd", ["/c", "start", "", "chrome", ...args]);
}

function chromeArgs(config = {}) {
  const args = [];
  const userDataDir = String(config.chrome_user_data_dir ?? "").trim();
  const profile = String(config.chrome_profile ?? "").trim();
  if (userDataDir) args.push(`--user-data-dir=${userDataDir}`);
  if (profile) args.push(`--profile-directory=${profile}`);
  return args;
}

export class SmartMpcServer {
  #config;
  #requestLog;
  #controlServer;
  #discoveryServer;
  #screenServer;
  #sessions = new Map();
  #server = null;
  #startedAt = null;

  constructor({ config = loadOrCreateConfig(), requestLog = new RequestLog() } = {}) {
    this.#config = config;
    this.#requestLog = requestLog;
    this.#controlServer = new ControlServer({ config: this.#config, requestLog: this.#requestLog });
    this.#discoveryServer = new DiscoveryServer({ config: this.#config, requestLog: this.#requestLog });
    this.#screenServer = new ScreenServer({ config: this.#config, requestLog: this.#requestLog });
  }

  get config() {
    return this.#config;
  }

  get running() {
    return Boolean(this.#server);
  }

  state() {
    const port = Number(this.#config.port ?? DEFAULT_PORT);
    return {
      app: APP_NAME,
      running: this.running,
      started_at: this.#startedAt,
      pc_id: this.#config.pc_id,
      pc_name: hostname(),
      host: this.#config.host,
      port,
      ips: localIps(),
      base_urls: baseUrls(port),
      pairing_token: this.#config.pairing_token,
      inbox_dir: this.#config.inbox_dir,
      outbox_dir: this.#config.outbox_dir,
      outbox_files: listFiles(this.#config.outbox_dir),
      active_sessions: this.#sessions.size,
      control: this.#controlServer.state(),
      discovery: this.#discoveryServer.state(),
      screen: this.#screenServer.state(),
      trusted_devices: Object.entries(this.#config.trusted_devices ?? {}).map(([id, device]) => ({
        id,
        name: device.name,
        trusted_at: device.trusted_at,
        last_seen_at: device.last_seen_at ?? null
      })),
      request_log: this.#requestLog.list()
    };
  }

  start() {
    if (this.#server) return Promise.resolve(this.state());

    const host = this.#config.host ?? "0.0.0.0";
    const port = Number(this.#config.port ?? DEFAULT_PORT);

    this.#server = createServer((req, res) => {
      this.#handleRequest(req, res).catch((error) => {
        this.#requestLog.add("server_error", { error: error.message });
        sendJson(res, 500, { ok: false, error: "Internal server error" });
      });
    });

    return new Promise((resolve, reject) => {
      const server = this.#server;

      server.once("error", (error) => {
        this.#server = null;
        this.#startedAt = null;
        reject(error);
      });

      server.listen(port, host, () => {
        this.#startedAt = new Date().toISOString();
        this.#requestLog.add("server_started", { port });
        this.#controlServer
          .start()
          .catch((error) => this.#requestLog.add("control_error", { error: error.message }))
          .then(() => this.#discoveryServer.start())
          .catch((error) => this.#requestLog.add("discovery_error", { error: error.message }))
          .then(() => this.#screenServer.start())
          .catch((error) => this.#requestLog.add("screen_error", { error: error.message }))
          .finally(() => resolve(this.state()));
      });
    });
  }

  async stop() {
    await this.#controlServer
      .stop()
      .catch((error) => this.#requestLog.add("control_error", { error: error.message }));
    await this.#discoveryServer
      .stop()
      .catch((error) => this.#requestLog.add("discovery_error", { error: error.message }));
    await this.#screenServer
      .stop()
      .catch((error) => this.#requestLog.add("screen_error", { error: error.message }));

    if (!this.#server) return this.state();

    return new Promise((resolve, reject) => {
      const server = this.#server;
      server.close((error) => {
        if (error) {
          reject(error);
          return;
        }
        this.#server = null;
        this.#startedAt = null;
        this.#sessions.clear();
        this.#requestLog.add("server_stopped");
        resolve(this.state());
      });
    });
  }

  revokeDevice(deviceId) {
    const id = String(deviceId ?? "").trim();
    if (!id || !this.#config.trusted_devices?.[id]) return this.state();

    const device = this.#config.trusted_devices[id];
    delete this.#config.trusted_devices[id];
    saveConfig(this.#config);
    this.#requestLog.add("device_revoked", { device: device.name ?? id });
    return this.state();
  }

  addFilesToOutbox(paths) {
    const copied = [];
    for (const source of paths ?? []) {
      const sourcePath = String(source ?? "");
      if (!sourcePath || !existsSync(sourcePath) || !statSync(sourcePath).isFile()) continue;
      const target = uniquePath(this.#config.outbox_dir, parse(sourcePath).base);
      copyFileSync(sourcePath, target);
      copied.push({ name: parse(target).base, source: parse(sourcePath).base });
    }
    if (copied.length) {
      this.#requestLog.add("outbox_files_added", { count: copied.length });
    }
    return { state: this.state(), copied };
  }

  async #handleRequest(req, res) {
    const requestUrl = new URL(req.url ?? "/", `http://${req.headers.host ?? "localhost"}`);
    const route = requestUrl.pathname;

    if (req.method === "OPTIONS") {
      sendJson(res, 200, { ok: true });
      return;
    }

    if (req.method === "GET" && route === "/health") {
      sendJson(res, 200, this.#healthBody());
      return;
    }

    if (req.method === "GET" && route === "/pair") {
      sendJson(res, 200, this.#pairBody());
      return;
    }

    if (req.method === "POST" && route === "/api/devices/register") {
      await this.#registerDevice(req, res);
      return;
    }

    const sessionPost = req.method === "POST" && (route === "/api/session/start" || route === "/api/session/stop");
    const protectedGet =
      req.method === "GET" &&
      (route === "/api/clipboard" ||
        route === "/api/request-files" ||
        route === "/api/request-files/download" ||
        route === "/api/server/state");
    const protectedPost = req.method === "POST" && (route === "/api/intent" || route === "/api/files" || sessionPost);

    if ((protectedGet || protectedPost) && !this.#isAuthorized(req)) {
      this.#requestLog.add("unauthorized", { route });
      sendJson(res, 401, { ok: false, error: "Unauthorized" });
      return;
    }

    if (req.method === "POST" && route === "/api/session/start") {
      const session = this.#startSession(req);
      sendJson(res, 200, { ok: true, ...session });
      return;
    }

    if (req.method === "POST" && route === "/api/session/stop") {
      const stopped = this.#stopSession(req);
      sendJson(res, 200, { ok: true, stopped });
      return;
    }

    if (req.method === "GET" && route === "/api/server/state") {
      sendJson(res, 200, { ok: true, state: this.state() });
      return;
    }

    if (req.method === "GET" && route === "/api/clipboard") {
      try {
        const text = await getClipboard();
        this.#requestLog.add("clipboard_requested", { bytes: Buffer.byteLength(text, "utf8") });
        sendJson(res, 200, { ok: true, text });
      } catch (error) {
        sendJson(res, 400, { ok: false, error: error.message });
      }
      return;
    }

    if (req.method === "GET" && route === "/api/request-files") {
      sendJson(res, 200, { ok: true, files: listFiles(this.#config.outbox_dir) });
      return;
    }

    if (req.method === "GET" && route === "/api/request-files/download") {
      try {
        const filename = requestUrl.searchParams.get("filename") ?? "";
        const target = safeChildPath(this.#config.outbox_dir, filename);
        if (!existsSync(target) || !statSync(target).isFile()) {
          sendJson(res, 404, { ok: false, error: "File not found" });
          return;
        }

        const data = readFileSync(target);
        this.#requestLog.add("file_requested", { filename: parse(target).base, bytes: data.length });
        res.writeHead(200, {
          "Content-Type": "application/octet-stream",
          "Content-Length": data.length,
          "Content-Disposition": `attachment; filename="${safeFilename(filename)}"`,
          "Access-Control-Allow-Origin": "*"
        });
        res.end(data);
      } catch (error) {
        sendJson(res, 400, { ok: false, error: error.message });
      }
      return;
    }

    if (req.method === "POST" && route === "/api/files") {
      try {
        const filename = requestUrl.searchParams.get("filename") ?? `upload-${Date.now()}.bin`;
        const body = await readBody(req);
        const target = uniquePath(this.#config.inbox_dir, filename);
        writeFileSync(target, body);
        this.#requestLog.add("file_uploaded", { filename: parse(target).base, bytes: body.length });
        sendJson(res, 200, { ok: true, saved_to: parse(target).base, bytes: body.length });
      } catch (error) {
        sendJson(res, 400, { ok: false, error: error.message });
      }
      return;
    }

    if (req.method === "POST" && route === "/api/intent") {
      try {
        const intent = await readJson(req);
        const result = await this.#handleIntent(intent);
        this.#requestLog.add("intent_received", { action: result.action ?? intent.type });
        sendJson(res, 200, { ok: true, result });
      } catch (error) {
        sendJson(res, 400, { ok: false, error: error.message });
      }
      return;
    }

    sendJson(res, 404, { ok: false, error: "Not found" });
  }

  #healthBody() {
    return {
      ok: true,
      app: APP_NAME,
      pc_id: this.#config.pc_id,
      pc_name: hostname(),
      time_ms: Date.now()
    };
  }

  #pairBody() {
    const port = Number(this.#config.port ?? DEFAULT_PORT);
    return {
      ok: true,
      app: APP_NAME,
      pc_id: this.#config.pc_id,
      pc_name: hostname(),
      port,
      ips: localIps(),
      base_urls: baseUrls(port)
    };
  }

  async #registerDevice(req, res) {
    if (!this.#isPairingAuthorized(req)) {
      this.#requestLog.add("register_denied", { reason: "invalid_pairing_token" });
      sendJson(res, 401, { ok: false, error: "Invalid pairing token" });
      return;
    }

    try {
      const registration = await readJson(req);
      const deviceId = String(registration.device_id ?? "").trim();
      const deviceName = String(registration.device_name ?? "Android device").trim();
      if (!deviceId) throw new Error("Missing device_id");

      const deviceToken = createDeviceToken();
      this.#config.trusted_devices[deviceId] = {
        name: deviceName,
        token: deviceToken,
        trusted_at: new Date().toISOString(),
        last_seen_at: null,
        registration_id: randomUUID()
      };
      saveConfig(this.#config);
      this.#requestLog.add("device_registered", { device: deviceName });

      sendJson(res, 200, {
        ok: true,
        pc_id: this.#config.pc_id,
        device_id: deviceId,
        device_token: deviceToken
      });
    } catch (error) {
      sendJson(res, 400, { ok: false, error: error.message });
    }
  }

  #isPairingAuthorized(req) {
    return req.headers[HEADER_PAIRING_TOKEN] === this.#config.pairing_token;
  }

  async #handleIntent(intent) {
    const type = intent?.type;
    const payload = intent?.payload ?? {};

    if (type === "url") {
      const url = String(payload.url ?? "").trim();
      if (!url) throw new Error("Missing payload.url");
      await openTarget(url);
      return { action: "url", opened: url };
    }

    if (type === "clipboard") {
      const text = String(payload.text ?? "");
      await setClipboard(text);
      return { action: "clipboard", bytes: Buffer.byteLength(text, "utf8") };
    }

    if (type === "file") {
      const filename = String(payload.filename ?? `file-${Date.now()}`);
      if (!payload.content_base64) throw new Error("Missing payload.content_base64");
      const data = Buffer.from(String(payload.content_base64), "base64");
      const target = uniquePath(this.#config.inbox_dir, filename);
      writeFileSync(target, data);
      return { action: "file", saved_to: parse(target).base, bytes: data.length };
    }

    if (type === "command") {
      const commandId = String(payload.command_id ?? "");
      return { action: "command", ...(await this.#runAllowedCommand(commandId)) };
    }

    if (type === "continue") {
      if (payload.url) return this.#handleIntent({ type: "url", payload: { url: payload.url } });
      if (payload.text) return this.#handleIntent({ type: "clipboard", payload: { text: payload.text } });
      throw new Error("Continue intent has no supported payload");
    }

    throw new Error(`Unsupported intent type: ${type}`);
  }

  async #runAllowedCommand(commandId) {
    const id = String(commandId ?? "").trim();
    if (!id) throw new Error("Missing command_id");

    if (id === "lock_pc") {
      await lockPc();
      return { command_id: id, result: "locked" };
    }

    if (id === "sleep_pc") {
      setTimeout(() => {
        sleepPc().catch((error) => this.#requestLog.add("command_error", { action: id, error: error.message }));
      }, 600);
      return { command_id: id, result: "sleep_requested" };
    }

    if (id === "open_chrome") {
      await openChrome(this.#config);
      return { command_id: id, result: "opened" };
    }

    const command = this.#config.allowed_commands?.[id];
    if (!command) throw new Error(`Command not allowed: ${id}`);

    if (command.type === "open_path" && command.target === "inbox") {
      await openTarget(this.#config.inbox_dir);
      return { command_id: id, target: "inbox", result: "opened" };
    }

    if (command.type === "open_path" && command.target === "outbox") {
      await openTarget(this.#config.outbox_dir);
      return { command_id: id, target: "outbox", result: "opened" };
    }

    if (command.type === "open_path" && command.path) {
      await openTarget(resolve(String(command.path)));
      return { command_id: id, result: "opened" };
    }

    if (command.type === "open_known_folder" && command.target === "downloads") {
      await openTarget(join(homedir(), "Downloads"));
      return { command_id: id, target: "downloads", result: "opened" };
    }

    if (command.type === "monitor_profile") {
      const profile = String(command.profile ?? "");
      const result = await switchMonitorProfile(profile);
      return { command_id: id, profile, result: "switched", monitor_switcher: result };
    }

    throw new Error(`Unsupported command: ${id}`);
  }

  #isAuthorized(req) {
    const sessionToken = String(req.headers[HEADER_SESSION_TOKEN] ?? "").trim();
    if (sessionToken && this.#sessions.has(sessionToken)) {
      const session = this.#sessions.get(sessionToken);
      session.last_seen_at = new Date().toISOString();
      return true;
    }

    const deviceId = String(req.headers[HEADER_DEVICE_ID] ?? "").trim();
    const deviceToken = String(req.headers[HEADER_DEVICE_TOKEN] ?? "").trim();
    const trustedDevice = this.#config.trusted_devices?.[deviceId];
    if (!trustedDevice || trustedDevice.token !== deviceToken) return false;

    trustedDevice.last_seen_at = new Date().toISOString();
    saveConfig(this.#config);
    return true;
  }

  #startSession(req) {
    const deviceId = String(req.headers[HEADER_DEVICE_ID] ?? "").trim();
    const trustedDevice = this.#config.trusted_devices?.[deviceId];
    const sessionToken = randomUUID().replaceAll("-", "");
    const now = new Date().toISOString();
    this.#sessions.set(sessionToken, {
      device_id: deviceId,
      device_name: trustedDevice?.name ?? deviceId,
      started_at: now,
      last_seen_at: now
    });
    this.#requestLog.add("session_started", { device: trustedDevice?.name ?? deviceId });
    return {
      session_token: sessionToken,
      device_id: deviceId,
      started_at: now
    };
  }

  #stopSession(req) {
    const sessionToken = String(req.headers[HEADER_SESSION_TOKEN] ?? "").trim();
    if (sessionToken && this.#sessions.delete(sessionToken)) {
      this.#requestLog.add("session_stopped");
      return true;
    }
    return false;
  }
}

export function sendJson(res, status, body) {
  const data = Buffer.from(JSON.stringify(body), "utf8");
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": data.length,
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type, X-Pairing-Token, X-Device-Id, X-Device-Token, X-Session-Token",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS"
  });
  res.end(data);
}

export function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let total = 0;

    req.on("data", (chunk) => {
      total += chunk.length;
      if (total > MAX_BODY_BYTES) {
        req.destroy(new Error("Request body too large"));
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

export async function readJson(req) {
  const body = await readBody(req);
  if (!body.length) return {};
  return JSON.parse(body.toString("utf8"));
}
