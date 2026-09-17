const api = window.smartMpc;

const subtitle = document.querySelector("#subtitle");
const serverStatus = document.querySelector("#serverStatus");
const toggleServerButton = document.querySelector("#toggleServerButton");
const errorPanel = document.querySelector("#errorPanel");
const pcName = document.querySelector("#pcName");
const port = document.querySelector("#port");
const controlStatus = document.querySelector("#controlStatus");
const discoveryStatus = document.querySelector("#discoveryStatus");
const screenStatus = document.querySelector("#screenStatus");
const pairingToken = document.querySelector("#pairingToken");
const copyTokenButton = document.querySelector("#copyTokenButton");
const baseUrlList = document.querySelector("#baseUrlList");
const openInboxButton = document.querySelector("#openInboxButton");
const openOutboxButton = document.querySelector("#openOutboxButton");
const addOutboxFilesButton = document.querySelector("#addOutboxFilesButton");
const startupToggle = document.querySelector("#startupToggle");
const outboxFileList = document.querySelector("#outboxFileList");
const deviceList = document.querySelector("#deviceList");
const deviceCount = document.querySelector("#deviceCount");
const logList = document.querySelector("#logList");
const logCount = document.querySelector("#logCount");

let currentState = null;
let startupSettings = null;
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

  for (const file of files) {
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
  setText(
    discoveryStatus,
    state?.discovery?.running ? `UDP ${state.discovery.port}` : "Stopped"
  );
  setText(
    screenStatus,
    state?.screen?.running ? `TCP ${state.screen.port} / ${state.screen.clients} client(s)` : "Stopped"
  );
  setText(pairingToken, showToken ? state?.pairing_token : "••••••••");
  renderBaseUrls(state?.base_urls ?? []);
  renderOutbox(state?.outbox_files ?? []);
  renderDevices(state?.trusted_devices ?? []);
  renderLogs(state?.request_log ?? []);
  showError(state?.startup_error ?? "");
}

let showToken = false;
const toggleTokenButton = document.querySelector("#toggleTokenButton");
const tokenEyeIcon = document.querySelector("#tokenEyeIcon");
if (toggleTokenButton) {
  toggleTokenButton.addEventListener("click", () => {
    showToken = !showToken;
    if (tokenEyeIcon) {
      tokenEyeIcon.innerHTML = showToken
        ? '<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/><line x1="1" y1="1" x2="23" y2="23"/>'
        : '<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/>';
    }
    if (currentState) render(currentState);
  });
}

function renderStartup(settings) {
  startupSettings = settings;
  startupToggle.checked = Boolean(settings?.enabled);
  startupToggle.disabled = !settings?.supported;
  startupToggle.closest(".toggle-row")?.classList.toggle("disabled", !settings?.supported);
}

async function refresh() {
  try {
    render(await api.getState());
    renderStartup(await api.getStartupSettings());
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

startupToggle.addEventListener("change", async () => {
  startupToggle.disabled = true;
  try {
    renderStartup(await api.setStartupEnabled(startupToggle.checked));
  } catch (error) {
    startupToggle.checked = Boolean(startupSettings?.enabled);
    showError(error.message);
  } finally {
    startupToggle.disabled = !startupSettings?.supported;
  }
});

const linkList = document.querySelector("#linkList");
const clearLinksButton = document.querySelector("#clearLinksButton");

let savedLinks = [];

function loadLinks() {
  try {
    savedLinks = JSON.parse(localStorage.getItem("smart_mpc_links") || "[]");
  } catch {
    savedLinks = [];
  }
  renderLinks();
}

function saveLinks() {
  localStorage.setItem("smart_mpc_links", JSON.stringify(savedLinks));
}

function renderLinks() {
  clearChildren(linkList);
  
  if (!savedLinks?.length) {
    const empty = document.createElement("p");
    empty.className = "empty";
    empty.textContent = "No links yet";
    linkList.append(empty);
    return;
  }

  for (const link of savedLinks) {
    const row = document.createElement("div");
    row.className = "link-row";

    const text = document.createElement("strong");
    text.textContent = link;
    text.title = link;

    const actions = document.createElement("div");
    actions.style.display = "flex";
    actions.style.gap = "6px";

    const copyBtn = document.createElement("button");
    copyBtn.type = "button";
    copyBtn.className = "icon-button";
    copyBtn.title = "Copy";
    copyBtn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>';
    copyBtn.addEventListener("click", () => api.copy(link));

    const openBtn = document.createElement("button");
    openBtn.type = "button";
    openBtn.className = "icon-button";
    openBtn.title = "Open in Browser";
    openBtn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"></circle><line x1="2" y1="12" x2="22" y2="12"></line><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"></path></svg>';
    openBtn.addEventListener("click", () => api.openUrl(link));

    const deleteBtn = document.createElement("button");
    deleteBtn.type = "button";
    deleteBtn.className = "icon-button danger";
    deleteBtn.title = "Delete";
    deleteBtn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path></svg>';
    deleteBtn.addEventListener("click", () => {
      savedLinks = savedLinks.filter(l => l !== link);
      saveLinks();
      renderLinks();
    });

    actions.append(copyBtn, openBtn, deleteBtn);
    row.append(text, actions);
    linkList.prepend(row);
  }
}

api.onLinksReceived((links) => {
  if (Array.isArray(links)) {
    for (const link of links) {
      if (typeof link === "string" && link.trim()) {
        savedLinks.push(link.trim());
      }
    }
    saveLinks();
    renderLinks();
  }
});

clearLinksButton.addEventListener("click", () => {
  savedLinks = [];
  saveLinks();
  renderLinks();
});

loadLinks();
refresh();
refreshTimer = setInterval(refresh, 2500);
window.addEventListener("beforeunload", () => {
  if (refreshTimer) clearInterval(refreshTimer);
});
