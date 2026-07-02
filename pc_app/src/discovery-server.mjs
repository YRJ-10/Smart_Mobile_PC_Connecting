import { createSocket } from "node:dgram";
import { hostname } from "node:os";
import { APP_NAME, DEFAULT_PORT } from "./constants.mjs";
import { baseUrls, localIps } from "./network.mjs";

const DISCOVERY_PORT = 8081;
const REQUEST = "DISCOVER_SMART_MPC";
const LEGACY_REQUEST = "DISCOVER_MOBILEPC";

export class DiscoveryServer {
  #config;
  #requestLog;
  #socket = null;

  constructor({ config, requestLog }) {
    this.#config = config;
    this.#requestLog = requestLog;
  }

  get running() {
    return Boolean(this.#socket);
  }

  state() {
    return {
      running: this.running,
      port: DISCOVERY_PORT
    };
  }

  start() {
    if (this.#socket) return Promise.resolve(this.state());

    const socket = createSocket({ type: "udp4", reuseAddr: true });
    this.#socket = socket;

    socket.on("message", (message, remote) => {
      this.#handleMessage(message, remote).catch((error) => {
        this.#requestLog.add("discovery_error", { error: error.message });
      });
    });

    return new Promise((resolveStart, reject) => {
      socket.once("error", (error) => {
        this.#socket = null;
        reject(error);
      });
      socket.bind(DISCOVERY_PORT, "0.0.0.0", () => {
        socket.setBroadcast(true);
        this.#requestLog.add("discovery_started", { port: DISCOVERY_PORT });
        resolveStart(this.state());
      });
    });
  }

  stop() {
    if (!this.#socket) return Promise.resolve(this.state());

    return new Promise((resolveStop) => {
      const socket = this.#socket;
      this.#socket = null;
      socket.close(() => {
        this.#requestLog.add("discovery_stopped");
        resolveStop(this.state());
      });
    });
  }

  async #handleMessage(message, remote) {
    const request = message.toString("utf8").trim();
    if (request !== REQUEST && request !== LEGACY_REQUEST) return;

    if (request === LEGACY_REQUEST) {
      this.#sendResponse("MOBILEPC_SERVER", remote);
      this.#sendResponse(JSON.stringify(this.#payload(false)), remote);
    } else {
      this.#sendResponse(JSON.stringify(this.#payload(false)), remote);
    }
    this.#requestLog.add("discovery_response", { target: remote.address });
  }

  #sendResponse(response, remote) {
    this.#socket?.send(Buffer.from(response, "utf8"), remote.port, remote.address);
  }

  #payload(legacy) {
    const port = Number(this.#config.port ?? DEFAULT_PORT);
    return {
      type: legacy ? "MOBILEPC_SERVER" : "SMART_MPC_SERVER",
      app: APP_NAME,
      pc_id: this.#config.pc_id,
      pc_name: hostname(),
      port,
      ips: localIps(),
      base_urls: baseUrls(port),
      control_port: 8080,
      discovery_port: DISCOVERY_PORT,
      audio_port: 8081,
      screen_port: 8082
    };
  }
}
