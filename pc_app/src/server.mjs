import { createServer } from "node:http";
import { randomUUID } from "node:crypto";
import { hostname } from "node:os";
import {
  APP_NAME,
  DEFAULT_PORT,
  HEADER_DEVICE_ID,
  HEADER_DEVICE_TOKEN,
  HEADER_PAIRING_TOKEN,
  MAX_BODY_BYTES
} from "./constants.mjs";
import { baseUrls, localIps } from "./network.mjs";
import { createDeviceToken, loadOrCreateConfig, saveConfig } from "./config.mjs";
import { RequestLog } from "./request-log.mjs";

export class SmartMpcServer {
  #config;
  #requestLog;
  #server = null;
  #startedAt = null;

  constructor({ config = loadOrCreateConfig(), requestLog = new RequestLog() } = {}) {
    this.#config = config;
    this.#requestLog = requestLog;
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
        resolve(this.state());
      });
    });
  }

  stop() {
    if (!this.#server) return Promise.resolve(this.state());

    return new Promise((resolve, reject) => {
      const server = this.#server;
      server.close((error) => {
        if (error) {
          reject(error);
          return;
        }
        this.#server = null;
        this.#startedAt = null;
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

    if (req.method === "GET" && route === "/api/server/state") {
      if (!this.#isAuthorized(req)) {
        this.#requestLog.add("unauthorized", { route });
        sendJson(res, 401, { ok: false, error: "Unauthorized" });
        return;
      }
      sendJson(res, 200, { ok: true, state: this.state() });
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

  #isAuthorized(req) {
    const deviceId = String(req.headers[HEADER_DEVICE_ID] ?? "").trim();
    const deviceToken = String(req.headers[HEADER_DEVICE_TOKEN] ?? "").trim();
    const trustedDevice = this.#config.trusted_devices?.[deviceId];
    if (!trustedDevice || trustedDevice.token !== deviceToken) return false;

    trustedDevice.last_seen_at = new Date().toISOString();
    saveConfig(this.#config);
    return true;
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
