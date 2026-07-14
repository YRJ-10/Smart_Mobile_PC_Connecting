import json
import socket
import struct
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
    import soundcard as sc
except Exception as exc:  # pragma: no cover - runtime environment dependent
    np = None
    sc = None
    AUDIO_IMPORT_ERROR = str(exc)
else:
    AUDIO_IMPORT_ERROR = ""

AUDIO_SAMPLE_RATE = 16000
AUDIO_CHANNELS = 1
AUDIO_NUMFRAMES = 256
AUDIO_PACKET_MAGIC = b"SMA1"

audio_thread = None
audio_stop_event = threading.Event()


def respond(ok, **payload):
    sys.stdout.write(json.dumps({"ok": ok, **payload}) + "\n")
    sys.stdout.flush()


def require_pyautogui():
    if pyautogui is None:
        raise RuntimeError(f"pyautogui unavailable: {IMPORT_ERROR}")


def require_audio():
    if sc is None or np is None:
        raise RuntimeError(f"audio unavailable: {AUDIO_IMPORT_ERROR}")


def execute_command(cmd):
    action_type = cmd.get("type")
    if action_type == "MOUSE_MOVE":
        require_pyautogui()
        pyautogui.moveRel(float(cmd.get("dx", 0)), float(cmd.get("dy", 0)))
    elif action_type == "MOUSE_CLICK":
        require_pyautogui()
        pyautogui.click(button=cmd.get("button", "left"))
    elif action_type == "MOUSE_DRAG":
        require_pyautogui()
        if cmd.get("action") == "down":
            pyautogui.mouseDown(button="left")
        elif cmd.get("action") == "up":
            pyautogui.mouseUp(button="left")
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
        execute_media_action(str(cmd.get("action", "")))
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
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 64 * 1024)
    target = (target_host, target_port)
    sequence = 0

    try:
        default_speaker = sc.default_speaker()
        microphones = sc.all_microphones(include_loopback=True)
        loopback_mic = next(
            (
                mic
                for mic in microphones
                if mic.isloopback and mic.name == default_speaker.name
            ),
            microphones[0],
        )

        with loopback_mic.recorder(
            samplerate=AUDIO_SAMPLE_RATE,
            channels=AUDIO_CHANNELS,
        ) as mic:
            while not audio_stop_event.is_set():
                audio = mic.record(numframes=AUDIO_NUMFRAMES)
                pcm = (
                    np.clip(audio * 32767.0, -32768, 32767)
                    .astype(np.int16)
                    .tobytes()
                )
                if pcm:
                    header = struct.pack(">4sI", AUDIO_PACKET_MAGIC, sequence & 0xFFFFFFFF)
                    sock.sendto(header + pcm, target)
                    sequence += 1
    except Exception as exc:
        respond(False, event="audio_error", error=str(exc))
    finally:
        sock.close()
        respond(True, event="audio_stopped")


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
    elif key in {"left", "right", "up", "down"}:
        pyautogui.press(key)
    else:
        pyautogui.press(key)


def execute_media_action(action):
    key_map = {
        "playpause": "playpause",
        "previous": "prevtrack",
        "next": "nexttrack",
        "stop": "stop",
        "mute": "volumemute",
        "volumeup": "volumeup",
        "volumedown": "volumedown",
    }
    key = key_map.get(action)
    if key:
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
