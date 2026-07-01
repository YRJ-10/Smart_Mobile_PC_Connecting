import json
import socket
import sys
import threading
import time

try:
    import pyautogui
except Exception as exc:  # pragma: no cover - runtime environment dependent
    pyautogui = None
    IMPORT_ERROR = str(exc)
else:
    IMPORT_ERROR = ""
    pyautogui.FAILSAFE = False
    pyautogui.PAUSE = 0

try:
    import numpy as np
    import sounddevice as sd
except Exception as exc:  # pragma: no cover - runtime environment dependent
    np = None
    sd = None
    AUDIO_IMPORT_ERROR = str(exc)
else:
    AUDIO_IMPORT_ERROR = ""

AUDIO_SAMPLE_RATE = 16000
AUDIO_CHANNELS = 1
AUDIO_BLOCKSIZE = 480

audio_thread = None
audio_stop_event = threading.Event()


def respond(ok, **payload):
    sys.stdout.write(json.dumps({"ok": ok, **payload}) + "\n")
    sys.stdout.flush()


def require_pyautogui():
    if pyautogui is None:
        raise RuntimeError(f"pyautogui unavailable: {IMPORT_ERROR}")


def require_audio():
    if sd is None or np is None:
        raise RuntimeError(f"audio unavailable: {AUDIO_IMPORT_ERROR}")


def execute_command(cmd):
    action_type = cmd.get("type")
    if action_type == "MOUSE_MOVE":
        require_pyautogui()
        pyautogui.moveRel(float(cmd.get("dx", 0)), float(cmd.get("dy", 0)))
    elif action_type == "MOUSE_CLICK":
        require_pyautogui()
        pyautogui.click(button=cmd.get("button", "left"))
    elif action_type == "TYPE_TEXT":
        require_pyautogui()
        text = str(cmd.get("text", ""))
        if text:
            pyautogui.write(text, interval=0.01)
    elif action_type == "SCROLL":
        require_pyautogui()
        dy = float(cmd.get("dy", 0))
        pyautogui.scroll(int(dy * 60))
    elif action_type == "SPECIAL_KEY":
        require_pyautogui()
        execute_special_key(str(cmd.get("key", "")))
    elif action_type == "ZOOM":
        require_pyautogui()
        zoom_delta = float(cmd.get("delta", 0))
        if zoom_delta != 0:
            pyautogui.keyDown("ctrl")
            pyautogui.scroll(150 if zoom_delta > 0 else -150)
            pyautogui.keyUp("ctrl")
    elif action_type == "MEDIA":
        require_pyautogui()
        if cmd.get("action") == "playpause":
            pyautogui.press("playpause")
    elif action_type in ("TOUCH_DOWN", "TOUCH_MOVE", "TOUCH_UP"):
        require_pyautogui()
        screen_width, screen_height = pyautogui.size()
        x = int(float(cmd.get("rx", 0.5)) * screen_width)
        y = int(float(cmd.get("ry", 0.5)) * screen_height)
        pyautogui.moveTo(x, y)
        if action_type == "TOUCH_DOWN":
            pyautogui.mouseDown(button="left")
        elif action_type == "TOUCH_UP":
            pyautogui.mouseUp(button="left")
    elif action_type == "AUDIO_TOGGLE":
        if bool(cmd.get("enabled")):
            start_audio_stream(str(cmd.get("target_host", "")), int(cmd.get("port", 0)))
        else:
            stop_audio_stream()
    else:
        raise ValueError(f"Unsupported command type: {action_type}")


def start_audio_stream(target_host, target_port):
    if not target_host or target_port <= 0:
        raise ValueError("Missing audio target")
    require_audio()
    stop_audio_stream()

    audio_stop_event.clear()
    thread = threading.Thread(
        target=audio_loop,
        args=(target_host, target_port),
        name="smart-mpc-audio",
        daemon=True,
    )
    globals()["audio_thread"] = thread
    thread.start()
    respond(True, event="audio_started", host=target_host, port=target_port)


def stop_audio_stream():
    audio_stop_event.set()
    thread = globals().get("audio_thread")
    if thread and thread.is_alive():
        thread.join(timeout=1.0)
    globals()["audio_thread"] = None


def audio_loop(target_host, target_port):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    target = (target_host, target_port)

    def callback(indata, frames, time_info, status):
        if audio_stop_event.is_set():
            raise sd.CallbackStop()
        audio = indata
        if audio.ndim > 1:
            audio = audio.mean(axis=1)
        pcm = np.clip(audio * 32767.0, -32768, 32767).astype(np.int16).tobytes()
        if pcm:
            sock.sendto(pcm, target)

    try:
        with open_loopback_stream(callback):
            while not audio_stop_event.is_set():
                time.sleep(0.05)
    except Exception as exc:
        respond(False, event="audio_error", error=str(exc))
    finally:
        sock.close()
        respond(True, event="audio_stopped")


def open_loopback_stream(callback):
    extra_settings = None
    device = None
    if sys.platform.startswith("win") and hasattr(sd, "WasapiSettings"):
        try:
            wasapi_host_api = next(
                index
                for index, api in enumerate(sd.query_hostapis())
                if "wasapi" in api.get("name", "").lower()
            )
            device = sd.query_hostapis(wasapi_host_api).get("default_output_device")
            extra_settings = sd.WasapiSettings(loopback=True)
        except Exception:
            device = None
            extra_settings = None

    return sd.InputStream(
        samplerate=AUDIO_SAMPLE_RATE,
        blocksize=AUDIO_BLOCKSIZE,
        channels=AUDIO_CHANNELS,
        dtype="float32",
        callback=callback,
        device=device,
        extra_settings=extra_settings,
    )


def execute_special_key(key):
    if not key:
        return
    if key == "copy":
        pyautogui.hotkey("ctrl", "c")
    elif key == "paste":
        pyautogui.hotkey("ctrl", "v")
    elif key == "alttab":
        pyautogui.keyDown("alt")
        pyautogui.press("tab")
        pyautogui.keyUp("alt")
    elif key == "browserback":
        pyautogui.hotkey("alt", "left")
    elif key == "browserforward":
        pyautogui.hotkey("alt", "right")
    else:
        pyautogui.press(key)


def main():
    respond(True, event="worker_ready")
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            command = json.loads(line)
            execute_command(command)
            respond(True, event="command_executed", command=command.get("type"))
        except Exception as exc:
            respond(False, error=str(exc))


if __name__ == "__main__":
    main()
