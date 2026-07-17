export class ScreenVideoCapture {
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
    track.contentHint = "motion";
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
      audio: false,
      video: {
        frameRate: { ideal: 30, max: 30 },
        cursor: "always"
      }
    });
    const videoTrack = stream.getVideoTracks()[0];
    if (!videoTrack) {
      for (const track of stream.getTracks()) track.stop();
      throw new Error("Desktop capture did not provide a video track");
    }
    for (const audioTrack of stream.getAudioTracks()) audioTrack.stop();
    videoTrack.contentHint = "motion";
    videoTrack.onended = () => {
      const affectedSessions = [...this.sessionTracks.keys()];
      this.stop();
      this.onSourceEnded(affectedSessions);
    };
    this.sourceStream = stream;
    this.sourceTrack = videoTrack;
  }
}

function defaultGetDisplayMedia(constraints) {
  return navigator.mediaDevices.getDisplayMedia(constraints);
}
