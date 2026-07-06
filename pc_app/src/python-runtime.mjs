import { existsSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { WORKER_DIR } from "./config.mjs";

export function workerInvocation(scriptPath, executableName) {
  const executablePath = join(WORKER_DIR, executableName);
  if (existsSync(executablePath)) {
    return { command: executablePath, args: [] };
  }
  return { command: pythonCommand(), args: [scriptPath] };
}

export function pythonCommand() {
  if (process.env.SMART_MPC_PYTHON) return process.env.SMART_MPC_PYTHON;

  const candidates = [
    ...localPythonCandidates(),
    "python"
  ];

  return candidates.find((candidate) => candidate === "python" || existsSync(candidate)) ?? "python";
}

function localPythonCandidates() {
  const root = process.env.LOCALAPPDATA ? join(process.env.LOCALAPPDATA, "Programs", "Python") : "";
  if (!root || !existsSync(root)) return [];

  return readdirSync(root, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => join(root, entry.name, "python.exe"))
    .filter((candidate) => existsSync(candidate))
    .sort()
    .reverse();
}
