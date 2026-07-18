import assert from "node:assert/strict";
import test from "node:test";

import { applyAudioPacketTime } from "../renderer/media-worker/sdp.js";

test("audio packet time is set to 10 ms without changing the video section", () => {
  const source = [
    "v=0",
    "o=- 1 2 IN IP4 127.0.0.1",
    "m=audio 9 UDP/TLS/RTP/SAVPF 111",
    "a=rtpmap:111 opus/48000/2",
    "a=ptime:20",
    "a=maxptime:60",
    "m=video 9 UDP/TLS/RTP/SAVPF 96",
    "a=rtpmap:96 H264/90000",
    "a=fmtp:96 packetization-mode=1"
  ].join("\r\n") + "\r\n";
  const originalVideo = source.slice(source.indexOf("m=video"));

  const result = applyAudioPacketTime(source, 10);

  assert.match(result, /\r\na=ptime:10\r\n/);
  assert.match(result, /\r\na=maxptime:10\r\n/);
  assert.doesNotMatch(result, /a=ptime:20/);
  assert.doesNotMatch(result, /a=maxptime:60/);
  assert.equal(result.slice(result.indexOf("m=video")), originalVideo);
  assert.equal(result.endsWith("\r\n"), true);
});

test("audio packet time tuning is idempotent and leaves video-only SDP alone", () => {
  const audio = "v=0\nm=audio 9 UDP/TLS/RTP/SAVPF 111\na=rtpmap:111 opus/48000/2\n";
  const once = applyAudioPacketTime(audio, 10);
  assert.equal(applyAudioPacketTime(once, 10), once);

  const video = "v=0\nm=video 9 UDP/TLS/RTP/SAVPF 96\na=rtpmap:96 VP8/90000\n";
  assert.equal(
    applyAudioPacketTime(video, 10),
    "v=0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=rtpmap:96 VP8/90000\r\n"
  );
});

test("audio packet time rejects invalid values", () => {
  assert.throws(() => applyAudioPacketTime("v=0", 0), /positive integer/);
  assert.throws(() => applyAudioPacketTime("v=0", 10.5), /positive integer/);
});
