const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("smartMpcMediaWorker", {
  ready: () => ipcRenderer.send("smart-mpc-media:ready"),
  sendEvent: (event) => ipcRenderer.send("smart-mpc-media:event", event),
  onCommand: (callback) => {
    ipcRenderer.on("smart-mpc-media:command", (_event, command) => callback(command));
  }
});
