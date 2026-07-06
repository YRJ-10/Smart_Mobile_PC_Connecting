import struct
import sys
import time

try:
    import cv2
    import mss
    import numpy as np
    import pyautogui
except Exception as exc:  # pragma: no cover - runtime environment dependent
    sys.stderr.write(f"screen dependencies unavailable: {exc}\n")
    sys.stderr.flush()
    raise

JPEG_QUALITY = 65
FRAME_SIZE = (1280, 720)
TARGET_FPS = 24

pyautogui.FAILSAFE = False
pyautogui.PAUSE = 0


def draw_cursor(frame, monitor):
    try:
        mouse_x, mouse_y = pyautogui.position()
    except Exception:
        return frame

    left = int(monitor.get("left", 0))
    top = int(monitor.get("top", 0))
    width = int(monitor.get("width", frame.shape[1]))
    height = int(monitor.get("height", frame.shape[0]))
    rel_x = mouse_x - left
    rel_y = mouse_y - top
    if rel_x < 0 or rel_y < 0 or rel_x >= width or rel_y >= height:
        return frame

    x = int(rel_x * FRAME_SIZE[0] / max(width, 1))
    y = int(rel_y * FRAME_SIZE[1] / max(height, 1))
    points = np.array(
        [
            [x, y],
            [x, y + 18],
            [x + 5, y + 15],
            [x + 9, y + 24],
            [x + 14, y + 22],
            [x + 10, y + 13],
            [x + 18, y + 13],
        ],
        dtype=np.int32,
    )
    cv2.polylines(frame, [points], True, (0, 0, 0), 3, lineType=cv2.LINE_AA)
    cv2.fillPoly(frame, [points], (255, 255, 255), lineType=cv2.LINE_AA)
    cv2.polylines(frame, [points], True, (20, 20, 20), 1, lineType=cv2.LINE_AA)
    return frame


def encode_frame(sct, monitor):
    image = np.array(sct.grab(monitor))
    frame = cv2.cvtColor(image, cv2.COLOR_BGRA2BGR)
    frame = cv2.resize(frame, FRAME_SIZE, interpolation=cv2.INTER_AREA)
    frame = draw_cursor(frame, monitor)
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
