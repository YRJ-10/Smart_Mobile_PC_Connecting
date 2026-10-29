import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import crypto from "node:crypto";

function base64UrlEncode(str) {
  return Buffer.from(str)
    .toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

export class FirebaseSync {
  constructor({ appRoot, onLinks, onClipboard, onMemo }) {
    this.appRoot = appRoot;
    this.onLinks = onLinks;
    this.onClipboard = onClipboard;
    this.onMemo = onMemo;

    this.serviceAccount = null;
    this.accessToken = null;
    this.tokenExpiresAt = 0;
    this.timer = null;
    this.isPolling = false;

    this.initServiceAccount();
  }

  initServiceAccount() {
    const credPath = join(this.appRoot, "firebase-service-account.json");
    if (!existsSync(credPath)) {
      console.log("[FirebaseSync] No firebase-service-account.json found. Cloud sync disabled.");
      return;
    }
    try {
      this.serviceAccount = JSON.parse(readFileSync(credPath, "utf-8"));
      console.log(`[FirebaseSync] Loaded credentials for project: ${this.serviceAccount.project_id}`);
    } catch (err) {
      console.error("[FirebaseSync] Failed to parse firebase-service-account.json:", err.message);
    }
  }

  async getAccessToken() {
    if (!this.serviceAccount) return null;
    const now = Math.floor(Date.now() / 1000);
    if (this.accessToken && this.tokenExpiresAt > now + 60) {
      return this.accessToken;
    }

    const header = { alg: "RS256", typ: "JWT" };
    const claim = {
      iss: this.serviceAccount.client_email,
      scope: "https://www.googleapis.com/auth/datastore",
      aud: "https://oauth2.googleapis.com/token",
      exp: now + 3600,
      iat: now
    };

    const input = `${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(JSON.stringify(claim))}`;
    const signer = crypto.createSign("RSA-SHA256");
    signer.update(input);
    const sig = signer.sign(this.serviceAccount.private_key, "base64")
      .replace(/=/g, "")
      .replace(/\+/g, "-")
      .replace(/\//g, "_");
    const jwt = `${input}.${sig}`;

    const res = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: jwt
      })
    });

    const data = await res.json();
    if (!res.ok) {
      throw new Error(data.error_description || "OAuth2 token request failed");
    }

    this.accessToken = data.access_token;
    this.tokenExpiresAt = now + (data.expires_in || 3600);
    return this.accessToken;
  }

  async pollQueue() {
    if (this.isPolling || !this.serviceAccount) return;
    this.isPolling = true;

    try {
      const token = await this.getAccessToken();
      if (!token) return;

      const url = `https://firestore.googleapis.com/v1/projects/${this.serviceAccount.project_id}/databases/(default)/documents/smart_mpc_queue`;
      const res = await fetch(url, {
        headers: { Authorization: `Bearer ${token}` }
      });

      if (!res.ok) {
        if (res.status === 404) return;
        console.error(`[FirebaseSync] Firestore error ${res.status}:`, await res.text());
        return;
      }

      const body = await res.json();
      const documents = body.documents || [];
      if (!documents.length) return;

      console.log(`[FirebaseSync] Found ${documents.length} pending item(s) in cloud queue.`);

      for (const doc of documents) {
        const item = this.parseDocument(doc);
        await this.processItem(item);
        await this.deleteDocument(doc.name, token);
      }
    } catch (err) {
      console.error("[FirebaseSync] Poll error:", err.message);
    } finally {
      this.isPolling = false;
    }
  }

  parseDocument(doc) {
    const id = doc.name.split("/").pop();
    const fields = doc.fields || {};
    const data = { _id: id, _name: doc.name };
    for (const [key, val] of Object.entries(fields)) {
      if ("stringValue" in val) data[key] = val.stringValue;
      else if ("booleanValue" in val) data[key] = val.booleanValue;
      else if ("integerValue" in val) data[key] = Number(val.integerValue);
      else if ("doubleValue" in val) data[key] = Number(val.doubleValue);
      else if ("timestampValue" in val) data[key] = val.timestampValue;
    }
    return data;
  }

  async processItem(item) {
    const type = item.type || "link";
    const content = item.content || "";

    if (type === "link" && content) {
      if (typeof this.onLinks === "function") {
        this.onLinks([{
          url: content,
          autoLaunch: Boolean(item.autoLaunch)
        }]);
      }
    } else if (type === "clipboard" && content) {
      if (typeof this.onClipboard === "function") {
        this.onClipboard(content);
      }
    } else if (type === "memo" && content) {
      if (typeof this.onMemo === "function") {
        this.onMemo({
          id: item._id,
          content: content,
          createdAt: item.createdAt || Date.now()
        });
      }
    }
  }

  async deleteDocument(docPath, token) {
    try {
      const url = `https://firestore.googleapis.com/v1/${docPath}`;
      await fetch(url, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${token}` }
      });
    } catch (err) {
      console.error(`[FirebaseSync] Failed to delete document ${docPath}:`, err.message);
    }
  }

  start(intervalMs = 10000) {
    if (!this.serviceAccount) return;
    this.pollQueue();
    if (this.timer) clearInterval(this.timer);
    this.timer = setInterval(() => this.pollQueue(), intervalMs);
    console.log(`[FirebaseSync] Cloud sync started (interval: ${intervalMs}ms).`);
  }

  stop() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    console.log("[FirebaseSync] Cloud sync stopped.");
  }
}
