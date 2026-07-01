import { MAX_REQUEST_LOGS } from "./constants.mjs";

export class RequestLog {
  #entries = [];

  add(type, detail = {}) {
    this.#entries.unshift({
      time: new Date().toISOString(),
      type,
      ...detail
    });
    this.#entries = this.#entries.slice(0, MAX_REQUEST_LOGS);
  }

  list() {
    return [...this.#entries];
  }
}
