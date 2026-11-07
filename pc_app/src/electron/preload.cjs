const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("smartMpc", {
  getState: () => ipcRenderer.invoke("server:getState"),
  startServer: () => ipcRenderer.invoke("server:start"),
  stopServer: () => ipcRenderer.invoke("server:stop"),
  revokeDevice: (deviceId) => ipcRenderer.invoke("server:revokeDevice", deviceId),
  getStartupSettings: () => ipcRenderer.invoke("app:getStartupSettings"),
  setStartupEnabled: (enabled) => ipcRenderer.invoke("app:setStartupEnabled", enabled),
  copy: (text) => ipcRenderer.invoke("ui:copy", text),
  openUrl: (url) => ipcRenderer.invoke("ui:openUrl", url),
  openInbox: () => ipcRenderer.invoke("ui:openInbox"),
  openOutbox: () => ipcRenderer.invoke("ui:openOutbox"),
  addFilesToOutbox: () => ipcRenderer.invoke("ui:addFilesToOutbox"),
  sendLinkToPhone: (url) => ipcRenderer.invoke("server:sendLinkToPhone", url),
  onLinksReceived: (callback) => ipcRenderer.on("links", (_event, links) => callback(links)),
  openCamViewer: () => ipcRenderer.invoke("cam:openViewer"),
  sendCamSignal: (signal) => ipcRenderer.invoke("cam:sendSignal", signal),
  onCamSignal: (callback) => {
    const handler = (_event, signal) => callback(signal);
    ipcRenderer.on("cam:signal", handler);
    return () => ipcRenderer.removeListener("cam:signal", handler);
  },
  setCamAlwaysOnTop: (flag) => ipcRenderer.invoke("cam:setAlwaysOnTop", flag),
  saveCamSnapshot: (dataUrl) => ipcRenderer.invoke("cam:saveSnapshot", dataUrl)
});
