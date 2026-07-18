import { app, BrowserWindow, clipboard, dialog, ipcMain, Menu, nativeImage, shell, Tray } from "electron";
import { existsSync, mkdirSync, unlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { SmartMpcServer } from "../server.mjs";
import { MediaWorkerProcess } from "../media/media-worker-process.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const appRoot = join(__dirname, "..", "..");
const rendererRoot = join(appRoot, "renderer");
const iconPath = app.isPackaged
  ? join(process.resourcesPath, "appicon.png")
  : join(appRoot, "assets", "appicon.png");
const mediaWorker = new MediaWorkerProcess();
const server = new SmartMpcServer({ mediaWorker });

let mainWindow = null;
let tray = null;
let isQuitting = false;

function startupFolderPath() {
  const appData = process.env.APPDATA;
  if (!appData) return "";
  return join(appData, "Microsoft", "Windows", "Start Menu", "Programs", "Startup");
}

function startupEntryPath() {
  const folder = startupFolderPath();
  return folder ? join(folder, "Smart MPC PC Server.vbs") : "";
}

function startupTargetPath() {
  return process.env.PORTABLE_EXECUTABLE_FILE || process.execPath;
}

function startupScript(targetPath) {
  const safeTarget = String(targetPath).replaceAll('"', '""');
  return [
    "Set shell = CreateObject(\"WScript.Shell\")",
    `shell.Run Chr(34) & "${safeTarget}" & Chr(34), 0, False`
  ].join("\r\n");
}

function disableLegacyLoginItem() {
  try {
    app.setLoginItemSettings({
      openAtLogin: false,
      path: process.execPath,
      args: []
    });
  } catch {
    // Best-effort cleanup for the previous portable-unfriendly startup method.
  }
}

function createWindow({ showOnReady = false } = {}) {
  mainWindow = new BrowserWindow({
    width: 1120,
    height: 760,
    minWidth: 920,
    minHeight: 640,
    title: "Smart MPC",
    backgroundColor: "#101417",
    icon: iconPath,
    show: false,
    webPreferences: {
      preload: join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  mainWindow.loadFile(join(rendererRoot, "index.html"));
  mainWindow.once("ready-to-show", () => {
    if (showOnReady) showMainWindow();
  });
  mainWindow.on("close", (event) => {
    if (isQuitting) return;
    event.preventDefault();
    mainWindow?.hide();
  });
  mainWindow.on("closed", () => {
    mainWindow = null;
  });
}

function showMainWindow() {
  if (!mainWindow) {
    createWindow({ showOnReady: true });
    return;
  }
  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.show();
  mainWindow.focus();
}

function createTray() {
  if (tray) return;
  const icon = nativeImage.createFromPath(iconPath);
  tray = new Tray(icon);
  tray.setToolTip("Smart MPC");
  tray.on("click", showMainWindow);
  tray.on("double-click", showMainWindow);
  updateTrayMenu();
}

function startupSettings() {
  const entryPath = startupEntryPath();
  const targetPath = startupTargetPath();
  return {
    supported: process.platform === "win32",
    enabled: Boolean(entryPath && existsSync(entryPath)),
    path: targetPath,
    entry_path: entryPath,
    method: "startup_folder"
  };
}

function setStartupEnabled(enabled) {
  if (process.platform !== "win32") {
    return startupSettings();
  }

  disableLegacyLoginItem();

  const folderPath = startupFolderPath();
  const entryPath = startupEntryPath();
  if (!folderPath || !entryPath) return { ...startupSettings(), supported: false };

  if (enabled) {
    mkdirSync(folderPath, { recursive: true });
    writeFileSync(entryPath, startupScript(startupTargetPath()), "utf8");
  } else if (existsSync(entryPath)) {
    unlinkSync(entryPath);
  }

  return startupSettings();
}

function updateTrayMenu() {
  if (!tray) return;
  const running = server.running;
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: "Show Smart MPC", click: showMainWindow },
    { type: "separator" },
    {
      label: running ? "Server running" : "Server stopped",
      enabled: false
    },
    {
      label: "Start Server",
      enabled: !running,
      click: async () => {
        await startServerSafely();
        updateTrayMenu();
      }
    },
    {
      label: "Stop Server",
      enabled: running,
      click: async () => {
        await server.stop();
        updateTrayMenu();
      }
    },
    { type: "separator" },
    {
      label: "Quit",
      click: () => {
        isQuitting = true;
        app.quit();
      }
    }
  ]));
}

async function startServerSafely() {
  try {
    const state = await server.start();
    updateTrayMenu();
    return state;
  } catch (error) {
    return {
      ...server.state(),
      startup_error: error.message
    };
  }
}

app.whenReady().then(async () => {
  await startServerSafely();
  createTray();
  createWindow({ showOnReady: false });

  app.on("activate", () => {
    showMainWindow();
  });
});

app.on("before-quit", async (event) => {
  if (!server.running) return;
  event.preventDefault();
  await server.stop();
  app.exit(0);
});

ipcMain.handle("server:getState", () => server.state());
ipcMain.handle("server:start", async () => {
  const state = await server.start();
  updateTrayMenu();
  return state;
});
ipcMain.handle("server:stop", async () => {
  const state = await server.stop();
  updateTrayMenu();
  return state;
});
ipcMain.handle("server:revokeDevice", (_event, deviceId) => server.revokeDevice(deviceId));
ipcMain.handle("app:getStartupSettings", () => startupSettings());
ipcMain.handle("app:setStartupEnabled", (_event, enabled) => setStartupEnabled(enabled));

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

ipcMain.handle("ui:addFilesToOutbox", async () => {
  const selection = await dialog.showOpenDialog(mainWindow, {
    title: "Add files to outbox",
    properties: ["openFile", "multiSelections"]
  });
  if (selection.canceled) return { state: server.state(), copied: [] };
  return server.addFilesToOutbox(selection.filePaths);
});
