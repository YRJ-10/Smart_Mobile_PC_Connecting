import { SmartMpcServer } from "./server.mjs";

const server = new SmartMpcServer();

function printStartup(state) {
  console.log(`${state.app}`);
  console.log(`Status: ${state.running ? "running" : "stopped"}`);
  console.log(`Port: ${state.port}`);
  console.log(`Pairing token: ${state.pairing_token}`);
  console.log("Base URLs:");
  for (const url of state.base_urls) {
    console.log(`- ${url}`);
  }
  console.log("Endpoints:");
  console.log("- GET /health");
  console.log("- GET /pair");
  console.log("- POST /api/devices/register");
  console.log("- GET /api/server/state");
}

try {
  const state = await server.start();
  printStartup(state);
} catch (error) {
  console.error(`Failed to start Smart MPC server: ${error.message}`);
  process.exitCode = 1;
}

async function shutdown() {
  await server.stop();
  process.exit(0);
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
