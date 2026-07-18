import { app, BrowserWindow } from "electron";
import { MediaWorkerProcess } from "./media-worker-process.mjs";

app.whenReady().then(async () => {
  // The tray app always keeps its main window alive; mirror that production topology.
  const hostWindow = new BrowserWindow({ show: false });
  const worker = new MediaWorkerProcess();
  try {
    const idle = worker.state();
    const cycles = [];
    for (let cycle = 1; cycle <= 3; cycle += 1) {
      process.stdout.write(`cycle=${cycle} start\n`);
      const firstId = `00000000-0000-0000-0000-${String(cycle).padStart(12, "0")}`;
      const secondId = `10000000-0000-0000-0000-${String(cycle).padStart(12, "0")}`;
      await Promise.all([
        worker.openSession({
          session_id: firstId,
          tracks: { audio: true, video: false }
        }),
        worker.openSession({
          session_id: secondId,
          tracks: { audio: false, video: true }
        })
      ]);
      const active = worker.state();
      await worker.closeSession(firstId);
      const oneRemaining = worker.state();
      await worker.closeSession(secondId);
      const stopped = worker.state();
      cycles.push({ active, oneRemaining, stopped });
      process.stdout.write(`cycle=${cycle} stopped\n`);
    }

    const result = {
      idle,
      cycles,
      lazyStart: !idle.running && cycles.every(({ active }) => (
        active.running && active.sessions === 2
      )),
      sharedWorker: cycles.every(({ oneRemaining }) => (
        oneRemaining.running && oneRemaining.sessions === 1
      )),
      cleanStop: cycles.every(({ stopped }) => (
        !stopped.running && stopped.sessions === 0
      ))
    };
    process.stdout.write(`${JSON.stringify(result)}\n`);
    hostWindow.destroy();
    app.exit(result.lazyStart && result.sharedWorker && result.cleanStop ? 0 : 1);
  } catch (error) {
    await worker.stop().catch(() => {});
    hostWindow.destroy();
    process.stderr.write(`Media worker probe failed: ${error.stack ?? error.message}\n`);
    app.exit(1);
  }
});
