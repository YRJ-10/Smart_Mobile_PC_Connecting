export class SystemAudioCapture {
  constructor({
    getDisplayMedia = defaultGetDisplayMedia,
    onSourceEnded = () => {}
  } = {}) {
    this.getDisplayMedia = getDisplayMedia;
    this.onSourceEnded = onSourceEnded;
    this.sourceStream = null;
    this.sourceTrack = null;
    this.sessionTracks = new Map();
    this.startPromise = null;
  }

  get active() {
    return Boolean(this.sourceTrack && this.sourceTrack.readyState !== "ended");
  }

  state() {
    return {
      active: this.active,
      sessions: this.sessionTracks.size,
      settings: this.sourceTrack?.getSettings?.() ?? null
    };
  }

  async acquire(sessionId) {
    if (this.sessionTracks.has(sessionId)) return this.sessionTracks.get(sessionId);
    await this.#ensureSource();
    const track = this.sourceTrack.clone();
    track.contentHint = "music";
    this.sessionTracks.set(sessionId, track);
    return track;
  }

  release(sessionId) {
    const track = this.sessionTracks.get(sessionId);
    if (!track) return;
    track.stop();
    this.sessionTracks.delete(sessionId);
    if (this.sessionTracks.size === 0) this.stop();
  }

  stop() {
    for (const track of this.sessionTracks.values()) track.stop();
    this.sessionTracks.clear();
    for (const track of this.sourceStream?.getTracks?.() ?? []) track.stop();
    this.sourceStream = null;
    this.sourceTrack = null;
    this.startPromise = null;
  }

  async #ensureSource() {
    if (this.active) return;
    if (this.startPromise) return this.startPromise;
    this.startPromise = this.#startSource();
    try {
      await this.startPromise;
    } finally {
      this.startPromise = null;
    }
  }

  async #startSource() {
    const stream = await this.getDisplayMedia({
      audio: true,
      video: {
        width: { max: 2 },
        height: { max: 2 },
        frameRate: { max: 1 }
      }
    });
    const audioTrack = stream.getAudioTracks()[0];
    if (!audioTrack) {
      for (const track of stream.getTracks()) track.stop();
      throw new Error("Windows loopback did not provide a system audio track");
    }
    for (const videoTrack of stream.getVideoTracks()) videoTrack.stop();
    audioTrack.contentHint = "music";
    audioTrack.onended = () => {
      const affectedSessions = [...this.sessionTracks.keys()];
      this.stop();
      this.onSourceEnded(affectedSessions);
    };
    this.sourceStream = stream;
    this.sourceTrack = audioTrack;
  }
}

function defaultGetDisplayMedia(constraints) {
  return navigator.mediaDevices.getDisplayMedia(constraints);
}
