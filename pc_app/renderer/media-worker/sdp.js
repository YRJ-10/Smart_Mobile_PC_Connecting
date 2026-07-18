export function applyAudioPacketTime(sdp, packetTimeMs = 10) {
  if (!Number.isInteger(packetTimeMs) || packetTimeMs <= 0) {
    throw new TypeError("Audio packet time must be a positive integer");
  }

  const lines = String(sdp ?? "")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .split("\n");
  while (lines.at(-1) === "") lines.pop();

  const audioStart = lines.findIndex((line) => /^m=audio(?:\s|$)/i.test(line));
  if (audioStart < 0) return `${lines.join("\r\n")}\r\n`;

  const nextMediaOffset = lines
    .slice(audioStart + 1)
    .findIndex((line) => /^m=/i.test(line));
  const audioEnd = nextMediaOffset < 0
    ? lines.length
    : audioStart + 1 + nextMediaOffset;
  const audioSection = lines
    .slice(audioStart, audioEnd)
    .filter((line) => !/^a=(?:max)?ptime:/i.test(line));
  audioSection.push(`a=ptime:${packetTimeMs}`);
  audioSection.push(`a=maxptime:${packetTimeMs}`);

  return [
    ...lines.slice(0, audioStart),
    ...audioSection,
    ...lines.slice(audioEnd)
  ].join("\r\n") + "\r\n";
}
