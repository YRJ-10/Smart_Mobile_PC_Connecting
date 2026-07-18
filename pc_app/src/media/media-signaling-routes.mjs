import { MediaSignalingError } from "./media-signaling-service.mjs";

const MEDIA_ROOT = "/api/media";
const SESSION_ROUTE = /^\/api\/media\/sessions\/([0-9a-f-]+)(?:\/(signals|status|stop))?$/i;

export function isMediaSignalingRoute(pathname) {
  return pathname === `${MEDIA_ROOT}/capabilities` ||
    pathname === `${MEDIA_ROOT}/sessions` ||
    SESSION_ROUTE.test(pathname);
}

export async function handleMediaSignalingRequest({
  req,
  res,
  requestUrl,
  deviceId,
  signaling,
  readJson,
  sendJson
}) {
  const route = requestUrl.pathname;

  try {
    if (req.method === "GET" && route === `${MEDIA_ROOT}/capabilities`) {
      sendJson(res, 200, { ok: true, capabilities: signaling.capabilities() });
      return;
    }

    if (req.method === "POST" && route === `${MEDIA_ROOT}/sessions`) {
      const session = signaling.createSession(deviceId, await readJson(req));
      sendJson(res, 201, { ok: true, session });
      return;
    }

    const match = SESSION_ROUTE.exec(route);
    if (!match) {
      sendJson(res, 404, { ok: false, error: "Not found" });
      return;
    }
    const [, sessionId, action = "status"] = match;

    if (req.method === "GET" && action === "status") {
      sendJson(res, 200, { ok: true, session: signaling.status(deviceId, sessionId) });
      return;
    }

    if (req.method === "POST" && action === "signals") {
      const signal = signaling.enqueueClientSignal(deviceId, sessionId, await readJson(req));
      sendJson(res, 202, { ok: true, signal });
      return;
    }

    if (req.method === "GET" && action === "signals") {
      const result = await signaling.readServerSignals(deviceId, sessionId, {
        after: requestUrl.searchParams.get("after") ?? 0,
        waitMs: requestUrl.searchParams.get("wait_ms") ?? 0
      });
      sendJson(res, 200, { ok: true, ...result });
      return;
    }

    if (req.method === "POST" && action === "stop") {
      signaling.stopSession(deviceId, sessionId);
      sendJson(res, 200, { ok: true, stopped: true });
      return;
    }

    sendJson(res, 405, { ok: false, error: "Method not allowed" });
  } catch (error) {
    const status = error instanceof MediaSignalingError ? error.status : 400;
    sendJson(res, status, { ok: false, error: error.message });
  }
}
