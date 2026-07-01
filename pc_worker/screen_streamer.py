import io
import struct
import sys
import time

try:
    import mss
    from PIL import Image
except Exception as exc:  # pragma: no cover - runtime environment dependent
    sys.stderr.write(f"screen dependencies unavailable: {exc}\n")
    sys.stderr.flush()
    raise

FPS = 8
JPEG_QUALITY = 55
MAX_WIDTH = 1280


def encode_frame(sct, monitor):
    shot = sct.grab(monitor)
    image = Image.frombytes("RGB", shot.size, shot.rgb)
    if image.width > MAX_WIDTH:
        height = int(image.height * (MAX_WIDTH / image.width))
        image = image.resize((MAX_WIDTH, height), Image.Resampling.BILINEAR)

    output = io.BytesIO()
    image.save(output, format="JPEG", quality=JPEG_QUALITY, optimize=True)
    return output.getvalue()


def main():
    interval = 1.0 / FPS
    with mss.mss() as sct:
        monitor = sct.monitors[1] if len(sct.monitors) > 1 else sct.monitors[0]
        while True:
            started = time.monotonic()
            frame = encode_frame(sct, monitor)
            sys.stdout.buffer.write(struct.pack(">I", len(frame)))
            sys.stdout.buffer.write(frame)
            sys.stdout.buffer.flush()

            elapsed = time.monotonic() - started
            if elapsed < interval:
                time.sleep(interval - elapsed)


if __name__ == "__main__":
    main()
