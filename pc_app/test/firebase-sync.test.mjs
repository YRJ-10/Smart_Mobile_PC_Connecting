import test from "node:test";
import assert from "node:assert/strict";
import { FirebaseSync } from "../src/firebase-sync.mjs";

test("FirebaseSync handles missing service account gracefully", () => {
  const sync = new FirebaseSync({
    appRoot: "non_existent_folder",
    onLinks: () => {},
    onClipboard: () => {},
    onMemo: () => {}
  });

  assert.equal(sync.serviceAccount, null);
  assert.equal(sync.timer, null);
  // calling start should not throw
  sync.start();
  assert.equal(sync.timer, null);
  sync.stop();
});

test("FirebaseSync parses Firestore document fields accurately", () => {
  const sync = new FirebaseSync({
    appRoot: "non_existent_folder",
    onLinks: () => {},
    onClipboard: () => {},
    onMemo: () => {}
  });

  const rawDoc = {
    name: "projects/test/databases/(default)/documents/smart_mpc_queue/doc123",
    fields: {
      type: { stringValue: "link" },
      content: { stringValue: "https://example.com" },
      autoLaunch: { booleanValue: true },
      createdAt: { integerValue: "1730000000000" }
    }
  };

  const parsed = sync.parseDocument(rawDoc);
  assert.equal(parsed._id, "doc123");
  assert.equal(parsed.type, "link");
  assert.equal(parsed.content, "https://example.com");
  assert.equal(parsed.autoLaunch, true);
  assert.equal(parsed.createdAt, 1730000000000);
});

test("FirebaseSync routes processItem to appropriate callbacks", async () => {
  let receivedLinks = null;
  let receivedClipboard = null;
  let receivedMemo = null;

  const sync = new FirebaseSync({
    appRoot: "non_existent_folder",
    onLinks: (links) => { receivedLinks = links; },
    onClipboard: (text) => { receivedClipboard = text; },
    onMemo: (memo) => { receivedMemo = memo; }
  });

  // Link
  await sync.processItem({ _id: "1", type: "link", content: "https://google.com", autoLaunch: true });
  assert.deepEqual(receivedLinks, [{ url: "https://google.com", autoLaunch: true }]);

  // Clipboard
  await sync.processItem({ _id: "2", type: "clipboard", content: "hello clipboard" });
  assert.equal(receivedClipboard, "hello clipboard");

  // Memo
  await sync.processItem({ _id: "3", type: "memo", content: "meeting at 9", createdAt: 12345 });
  assert.deepEqual(receivedMemo, { id: "3", content: "meeting at 9", createdAt: 12345 });
});
