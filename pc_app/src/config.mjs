import { randomUUID } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { DEFAULT_HOST, DEFAULT_PORT } from "./constants.mjs";

const SRC_DIR = dirname(fileURLToPath(import.meta.url));
export const APP_DIR = dirname(SRC_DIR);
const IS_PACKAGED = APP_DIR.includes(".asar");
export const RUNTIME_DIR =
  process.env.SMART_MPC_RUNTIME_DIR ||
  (IS_PACKAGED
    ? join(process.env.APPDATA || dirname(process.execPath), "Smart MPC")
    : APP_DIR);
export const WORKER_DIR =
  process.env.SMART_MPC_WORKER_DIR ||
  (IS_PACKAGED && process.resourcesPath
    ? join(process.resourcesPath, "pc_worker")
    : resolve(APP_DIR, "..", "pc_worker"));
export const CONFIG_PATH = join(RUNTIME_DIR, "config.json");
export const DEFAULT_INBOX_DIR = join(RUNTIME_DIR, "inbox");
export const DEFAULT_OUTBOX_DIR = join(RUNTIME_DIR, "outbox");

function token() {
  return randomUUID().replaceAll("-", "");
}

function defaultAllowedCommands() {
  return {
    open_inbox: { type: "open_path", target: "inbox" },
    open_outbox: { type: "open_path", target: "outbox" },
    open_downloads: { type: "open_known_folder", target: "downloads" },
    open_chrome: { type: "pc_action" },
    lock_pc: { type: "pc_action" },
    sleep_pc: { type: "pc_action" },
    monitor_profile_1: { type: "monitor_profile", profile: "1" },
    monitor_profile_2: { type: "monitor_profile", profile: "2" },
    monitor_profile_3: { type: "monitor_profile", profile: "3" },
    monitor_profile_4: { type: "monitor_profile", profile: "4" },
    monitor_profile_5: { type: "monitor_profile", profile: "5" },
    monitor_profile_6: { type: "monitor_profile", profile: "6" }
  };
}

function defaultConfig() {
  return {
    schema_version: 1,
    pc_id: randomUUID(),
    host: DEFAULT_HOST,
    port: DEFAULT_PORT,
    pairing_token: token(),
    trusted_devices: {},
    inbox_dir: DEFAULT_INBOX_DIR,
    outbox_dir: DEFAULT_OUTBOX_DIR,
    chrome_profile: "",
    chrome_user_data_dir: "",
    allowed_commands: defaultAllowedCommands()
  };
}

function normalizeConfig(config) {
  let changed = false;
  const next = { ...config };

  if (!next.schema_version) {
    next.schema_version = 1;
    changed = true;
  }
  if (!next.pc_id) {
    next.pc_id = randomUUID();
    changed = true;
  }
  if (!next.host) {
    next.host = DEFAULT_HOST;
    changed = true;
  }
  if (!next.port) {
    next.port = DEFAULT_PORT;
    changed = true;
  }
  if (!next.pairing_token) {
    next.pairing_token = token();
    changed = true;
  }
  if (!next.trusted_devices) {
    next.trusted_devices = {};
    changed = true;
  }
  if (!next.inbox_dir) {
    next.inbox_dir = DEFAULT_INBOX_DIR;
    changed = true;
  }
  if (!next.outbox_dir) {
    next.outbox_dir = DEFAULT_OUTBOX_DIR;
    changed = true;
  }
  if (next.chrome_profile == null) {
    next.chrome_profile = "";
    changed = true;
  }
  if (next.chrome_user_data_dir == null) {
    next.chrome_user_data_dir = "";
    changed = true;
  }
  const defaults = defaultAllowedCommands();
  if (!next.allowed_commands) {
    next.allowed_commands = defaults;
    changed = true;
  } else {
    for (const [id, command] of Object.entries(defaults)) {
      if (!next.allowed_commands[id]) {
        next.allowed_commands[id] = command;
        changed = true;
      }
    }
  }

  return { config: next, changed };
}

export function loadOrCreateConfig() {
  if (!existsSync(CONFIG_PATH)) {
    const created = defaultConfig();
    ensureRuntimeDirs(created);
    writeFileSync(CONFIG_PATH, JSON.stringify(created, null, 2), "utf8");
    return created;
  }

  const parsed = JSON.parse(readFileSync(CONFIG_PATH, "utf8"));
  const { config, changed } = normalizeConfig(parsed);
  ensureRuntimeDirs(config);
  if (changed) saveConfig(config);
  return config;
}

export function saveConfig(config) {
  writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2), "utf8");
}

export function ensureRuntimeDirs(config) {
  mkdirSync(config.inbox_dir ?? DEFAULT_INBOX_DIR, { recursive: true });
  mkdirSync(config.outbox_dir ?? DEFAULT_OUTBOX_DIR, { recursive: true });
}

export function createDeviceToken() {
  return token();
}
