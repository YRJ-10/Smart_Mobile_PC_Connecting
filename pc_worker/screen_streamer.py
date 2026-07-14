import struct
import sys
import time

try:
    import cv2
    import mss
    import numpy as np
except Exception as exc:  # pragma: no cover - runtime environment dependent
    sys.stderr.write(f"screen dependencies unavailable: {exc}\n")
    sys.stderr.flush()
    raise

JPEG_QUALITY = 65
FRAME_SIZE = (1280, 720)
TARGET_FPS = 24

def encode_frame(sct, monitor):
    image = np.array(sct.grab(monitor))
    frame = cv2.cvtColor(image, cv2.COLOR_BGRA2BGR)
    frame = cv2.resize(frame, FRAME_SIZE, interpolation=cv2.INTER_AREA)
    ok, jpeg = cv2.imencode(
        ".jpg",
        frame,
        [int(cv2.IMWRITE_JPEG_QUALITY), JPEG_QUALITY],
    )
    if not ok:
        return b""
    return jpeg.tobytes()


def main():
    frame_interval = 1.0 / TARGET_FPS
    next_frame_at = time.perf_counter()
    with mss.mss() as sct:
        monitor = sct.monitors[1] if len(sct.monitors) > 1 else sct.monitors[0]
        while True:
            now = time.perf_counter()
            if now < next_frame_at:
                time.sleep(next_frame_at - now)
            next_frame_at = time.perf_counter() + frame_interval

            frame = encode_frame(sct, monitor)
            if not frame:
                continue
            sys.stdout.buffer.write(struct.pack(">I", len(frame)))
            sys.stdout.buffer.write(frame)
            sys.stdout.buffer.flush()


if __name__ == "__main__":
    main()
