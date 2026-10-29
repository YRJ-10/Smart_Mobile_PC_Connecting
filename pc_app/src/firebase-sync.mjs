import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { Firestore } from "@google-cloud/firestore";

export class FirebaseSync {
  constructor({ appRoot, onLinks, onClipboard, onMemo }) {
    this.appRoot = appRoot;
    this.onLinks = onLinks;
    this.onClipboard = onClipboard;
    this.onMemo = onMemo;

    this.serviceAccount = null;
    this.db = null;
    this.unsubscribe = null;
    this.timer = null;

    this.initServiceAccount();
  }

  initServiceAccount() {
    const candidates = [
      join(this.appRoot, "firebase-service-account.json"),
      process.resourcesPath ? join(process.resourcesPath, "firebase-service-account.json") : null,
      join(process.env.APPDATA || "", "Smart MPC", "firebase-service-account.json"),
      join(process.cwd(), "firebase-service-account.json"),
      join(process.cwd(), "pc_app", "firebase-service-account.json")
    ];

    // For test isolation: if appRoot was explicitly given and contains non_existent, don't use fallbacks
    const isTestFolder = typeof this.appRoot === "string" && this.appRoot.includes("non_existent");
    const credPath = isTestFolder
      ? join(this.appRoot, "firebase-service-account.json")
      : candidates.find((p) => p && existsSync(p));

    if (!credPath || !existsSync(credPath)) {
      console.log("[FirebaseSync] No firebase-service-account.json found. Cloud sync disabled.");
      return;
    }

    try {
      this.serviceAccount = JSON.parse(readFileSync(credPath, "utf-8"));
      this.db = new Firestore({
        projectId: this.serviceAccount.project_id,
        credentials: {
          client_email: this.serviceAccount.client_email,
          private_key: this.serviceAccount.private_key
        }
      });
      console.log(`[FirebaseSync] Loaded credentials from ${credPath} for project: ${this.serviceAccount.project_id}`);
    } catch (err) {
      console.error("[FirebaseSync] Failed to parse firebase-service-account.json:", err.message);
    }
  }

  parseDocument(doc) {
    const id = doc.name ? doc.name.split("/").pop() : (doc.id || "");
    const fields = doc.fields || {};
    const data = { _id: id, _name: doc.name || "" };
    for (const [key, val] of Object.entries(fields)) {
      if ("stringValue" in val) data[key] = val.stringValue;
      else if ("booleanValue" in val) data[key] = val.booleanValue;
      else if ("integerValue" in val) data[key] = Number(val.integerValue);
      else if ("doubleValue" in val) data[key] = Number(val.doubleValue);
      else if ("timestampValue" in val) data[key] = val.timestampValue;
    }
    return data;
  }

  start() {
    if (!this.db) {
      console.log("[FirebaseSync] Cloud sync disabled (no database).");
      return;
    }
    if (this.unsubscribe) {
      this.stop();
    }

    console.log("[FirebaseSync] Starting realtime Firestore listener...");
    try {
      this.unsubscribe = this.db.collection("smart_mpc_queue").onSnapshot(
        async (snapshot) => {
          for (const change of snapshot.docChanges()) {
            if (change.type === "added") {
              const doc = change.doc;
              const data = { _id: doc.id, ...doc.data() };
              console.log(`[FirebaseSync] Realtime item received: ${data.type || "unknown"} (${doc.id})`);
              await this.processItem(data);
              try {
                await doc.ref.delete();
                console.log(`[FirebaseSync] Cleaned up item: ${doc.id}`);
              } catch (delErr) {
                console.error(`[FirebaseSync] Failed to delete document ${doc.id}:`, delErr.message);
              }
            }
          }
        },
        (err) => {
          console.error("[FirebaseSync] Realtime listener error:", err.message);
        }
      );
      console.log("[FirebaseSync] Realtime Firestore listener active (instant push, 0 idle reads).");
    } catch (err) {
      console.error("[FirebaseSync] Failed to attach realtime listener:", err.message);
    }
  }

  stop() {
    if (this.unsubscribe) {
      this.unsubscribe();
      this.unsubscribe = null;
      console.log("[FirebaseSync] Realtime Firestore listener stopped.");
    }
  }

  async processItem(item) {
    const type = item.type || "link";
    const content = item.content || "";

    if (type === "link" && content) {
      if (typeof this.onLinks === "function") {
        this.onLinks([
          {
            url: content,
            autoLaunch: Boolean(item.autoLaunch)
          }
        ]);
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
}
