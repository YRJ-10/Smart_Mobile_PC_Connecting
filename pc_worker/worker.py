import json
import sys

try:
    import pyautogui
except Exception as exc:  # pragma: no cover - runtime environment dependent
    pyautogui = None
    IMPORT_ERROR = str(exc)
else:
    IMPORT_ERROR = ""
    pyautogui.FAILSAFE = False
    pyautogui.PAUSE = 0


def respond(ok, **payload):
    sys.stdout.write(json.dumps({"ok": ok, **payload}) + "\n")
    sys.stdout.flush()


def require_pyautogui():
    if pyautogui is None:
        raise RuntimeError(f"pyautogui unavailable: {IMPORT_ERROR}")


def execute_command(cmd):
    require_pyautogui()

    action_type = cmd.get("type")
    if action_type == "MOUSE_MOVE":
        pyautogui.moveRel(float(cmd.get("dx", 0)), float(cmd.get("dy", 0)))
    elif action_type == "MOUSE_CLICK":
        pyautogui.click(button=cmd.get("button", "left"))
    elif action_type == "TYPE_TEXT":
        text = str(cmd.get("text", ""))
        if text:
            pyautogui.write(text, interval=0.01)
    elif action_type == "SCROLL":
        dy = float(cmd.get("dy", 0))
        pyautogui.scroll(int(dy * 60))
    elif action_type == "SPECIAL_KEY":
        execute_special_key(str(cmd.get("key", "")))
    elif action_type == "ZOOM":
        zoom_delta = float(cmd.get("delta", 0))
        if zoom_delta != 0:
            pyautogui.keyDown("ctrl")
            pyautogui.scroll(150 if zoom_delta > 0 else -150)
            pyautogui.keyUp("ctrl")
    elif action_type == "MEDIA":
        if cmd.get("action") == "playpause":
            pyautogui.press("playpause")
    elif action_type in ("TOUCH_DOWN", "TOUCH_MOVE", "TOUCH_UP"):
        screen_width, screen_height = pyautogui.size()
        x = int(float(cmd.get("rx", 0.5)) * screen_width)
        y = int(float(cmd.get("ry", 0.5)) * screen_height)
        pyautogui.moveTo(x, y)
        if action_type == "TOUCH_DOWN":
            pyautogui.mouseDown(button="left")
        elif action_type == "TOUCH_UP":
            pyautogui.mouseUp(button="left")
    elif action_type == "AUDIO_TOGGLE":
        pass
    else:
        raise ValueError(f"Unsupported command type: {action_type}")


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
