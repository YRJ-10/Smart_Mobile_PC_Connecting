import { networkInterfaces } from "node:os";

export function localIps() {
  const addresses = [];

  for (const entries of Object.values(networkInterfaces())) {
    for (const entry of entries ?? []) {
      if (entry.family === "IPv4" && !entry.internal) {
        addresses.push(entry.address);
      }
    }
  }

  return [...new Set(addresses)].sort();
}

export function baseUrls(port) {
  return localIps().map((ip) => `http://${ip}:${port}`);
}
