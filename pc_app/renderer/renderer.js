const api = window.smartMpc;

const subtitle = document.querySelector("#subtitle");
const serverStatus = document.querySelector("#serverStatus");
const toggleServerButton = document.querySelector("#toggleServerButton");
const errorPanel = document.querySelector("#errorPanel");
const pcName = document.querySelector("#pcName");
const port = document.querySelector("#port");
const controlStatus = document.querySelector("#controlStatus");
const pairingToken = document.querySelector("#pairingToken");
const copyTokenButton = document.querySelector("#copyTokenButton");
const baseUrlList = document.querySelector("#baseUrlList");
const openInboxButton = document.querySelector("#openInboxButton");
const openOutboxButton = document.querySelector("#openOutboxButton");
const addOutboxFilesButton = document.querySelector("#addOutboxFilesButton");
const outboxFileList = document.querySelector("#outboxFileList");
const deviceList = document.querySelector("#deviceList");
const deviceCount = document.querySelector("#deviceCount");
const logList = document.querySelector("#logList");
const logCount = document.querySelector("#logCount");

let currentState = null;
let refreshTimer = null;

function setText(element, value) {
  element.textContent = value == null || value === "" ? "-" : String(value);
}

function formatDate(value) {
  if (!value) return "Never";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return date.toLocaleString();
}

function showError(message) {
  if (!message) {
    errorPanel.classList.add("hidden");
    errorPanel.textContent = "";
    return;
  }
  errorPanel.textContent = message;
  errorPanel.classList.remove("hidden");
}

function clearChildren(element) {
  while (element.firstChild) element.removeChild(element.firstChild);
}

function renderBaseUrls(urls) {
  clearChildren(baseUrlList);
  if (!urls?.length) {
    const empty = document.createElement("p");
    empty.className = "empty";
    empty.textContent = "No network address detected";
    baseUrlList.append(empty);
    return;
  }

  for (const url of urls) {
    const row = document.createElement("button");
    row.className = "url-row";
    row.type = "button";
    row.textContent = url;
    row.addEventListener("click", () => api.copy(url));
    baseUrlList.append(row);
  }
}

function renderDevices(devices) {
  clearChildren(deviceList);
  deviceCount.textContent = String(devices?.length ?? 0);

  if (!devices?.length) {
    const empty = document.createElement("p");
    empty.className = "empty";
    empty.textContent = "No trusted devices yet";
    deviceList.append(empty);
    return;
  }

  for (const device of devices) {
    const row = document.createElement("div");
    row.className = "list-row";

    const body = document.createElement("div");
    const name = document.createElement("strong");
    name.textContent = device.name || "Android device";
    const meta = document.createElement("span");
    meta.textContent = `Trusted ${formatDate(device.trusted_at)} | Last seen ${formatDate(device.last_seen_at)}`;
    body.append(name, meta);

    const button = document.createElement("button");
    button.className = "danger";
    button.type = "button";
    button.textContent = "Revoke";
    button.addEventListener("click", async () => {
      currentState = await api.revokeDevice(device.id);
      render(currentState);
    });

    row.append(body, button);
    deviceList.append(row);
  }
}

function renderOutbox(files) {
  clearChildren(outboxFileList);

  if (!files?.length) {
    const empty = document.createElement("p");
    empty.className = "empty compact";
    empty.textContent = "No shared files";
    outboxFileList.append(empty);
    return;
  }

  for (const file of files.slice(0, 5)) {
    const row = document.createElement("div");
    row.className = "mini-row";
    const name = document.createElement("span");
    name.textContent = file.name;
    const size = document.createElement("strong");
    size.textContent = formatBytes(file.bytes ?? 0);
    row.append(name, size);
    outboxFileList.append(row);
  }
}

function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  const kb = bytes / 1024;
  if (kb < 1024) return `${kb.toFixed(1)} KB`;
  const mb = kb / 1024;
  if (mb < 1024) return `${mb.toFixed(1)} MB`;
  return `${(mb / 1024).toFixed(1)} GB`;
}

function renderLogs(logs) {
  clearChildren(logList);
  logCount.textContent = String(logs?.length ?? 0);

  if (!logs?.length) {
    const empty = document.createElement("p");
    empty.className = "empty";
    empty.textContent = "No activity yet";
    logList.append(empty);
    return;
  }

  for (const log of logs) {
    const row = document.createElement("div");
    row.className = "list-row log-row";

    const type = document.createElement("strong");
    type.textContent = log.type ?? "event";
    const time = document.createElement("span");
    time.textContent = formatDate(log.time);

    row.append(type, time);
    logList.append(row);
  }
}

function render(state) {
  currentState = state;
  const running = Boolean(state?.running);

  document.body.classList.toggle("server-running", running);
  setText(subtitle, state?.app);
  serverStatus.textContent = running ? "Running" : "Stopped";
  serverStatus.className = running ? "status-pill running" : "status-pill stopped";
  toggleServerButton.textContent = running ? "Stop Server" : "Start Server";

  setText(pcName, state?.pc_name);
  setText(port, state?.port);
  setText(
    controlStatus,
    state?.control?.running ? `TCP ${state.control.port} / ${state.control.clients} client(s)` : "Stopped"
  );
  setText(pairingToken, state?.pairing_token);
  renderBaseUrls(state?.base_urls ?? []);
  renderOutbox(state?.outbox_files ?? []);
  renderDevices(state?.trusted_devices ?? []);
  renderLogs(state?.request_log ?? []);
  showError(state?.startup_error ?? "");
}

async function refresh() {
  try {
    render(await api.getState());
  } catch (error) {
    showError(error.message);
  }
}

toggleServerButton.addEventListener("click", async () => {
  toggleServerButton.disabled = true;
  try {
    const next = currentState?.running ? await api.stopServer() : await api.startServer();
    render(next);
  } catch (error) {
    showError(error.message);
  } finally {
    toggleServerButton.disabled = false;
  }
});

copyTokenButton.addEventListener("click", () => api.copy(currentState?.pairing_token ?? ""));
openInboxButton.addEventListener("click", () => api.openInbox());
openOutboxButton.addEventListener("click", () => api.openOutbox());
addOutboxFilesButton.addEventListener("click", async () => {
  const result = await api.addFilesToOutbox();
  render(result.state);
});

refresh();
refreshTimer = setInterval(refresh, 2500);
window.addEventListener("beforeunload", () => {
  if (refreshTimer) clearInterval(refreshTimer);
});
