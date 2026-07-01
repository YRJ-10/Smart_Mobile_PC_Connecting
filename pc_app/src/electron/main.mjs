import { app, BrowserWindow, clipboard, ipcMain, shell } from "electron";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { SmartMpcServer } from "../server.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const appRoot = join(__dirname, "..", "..");
const rendererRoot = join(appRoot, "renderer");
const server = new SmartMpcServer();

let mainWindow = null;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1120,
    height: 760,
    minWidth: 920,
    minHeight: 640,
    title: "Smart MPC",
    backgroundColor: "#101417",
    show: false,
    webPreferences: {
      preload: join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  mainWindow.loadFile(join(rendererRoot, "index.html"));
  mainWindow.once("ready-to-show", () => {
    mainWindow?.show();
  });
  mainWindow.on("closed", () => {
    mainWindow = null;
  });
}

async function startServerSafely() {
  try {
    return await server.start();
  } catch (error) {
    return {
      ...server.state(),
      startup_error: error.message
    };
  }
}

app.whenReady().then(async () => {
  await startServerSafely();
  createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("before-quit", async (event) => {
  if (!server.running) return;
  event.preventDefault();
  await server.stop();
  app.exit(0);
});

ipcMain.handle("server:getState", () => server.state());
ipcMain.handle("server:start", () => server.start());
ipcMain.handle("server:stop", () => server.stop());
ipcMain.handle("server:revokeDevice", (_event, deviceId) => server.revokeDevice(deviceId));

ipcMain.handle("ui:copy", (_event, text) => {
  clipboard.writeText(String(text ?? ""));
  return true;
});

ipcMain.handle("ui:openInbox", async () => {
  return shell.openPath(server.config.inbox_dir);
});

ipcMain.handle("ui:openOutbox", async () => {
  return shell.openPath(server.config.outbox_dir);
});
