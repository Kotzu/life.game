"""
Mac Bridge - server minimal pe MacBook.
Primeste comenzi de la BotBridge (iPhone) via WiFi si:
  - Porneste / opreste TouchRunner (XCTest) pe iPhone via tidevice
  - Raporteaza statusul

Rulare automata la boot Mac:
  python3 mac_bridge.py --install-launchagent

Dupa instalare: ruleaza singur la fiecare pornire Mac, fara interactiune.
"""

import argparse
import os
import signal
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = 7753
TOUCH_BUNDLE = "com.aibot.BotBridgeTouch"

_tidevice_proc: subprocess.Popen | None = None
_lock = threading.Lock()


# ── HTTP Handler ─────────────────────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        print(f"[{self.address_string()}] {format % args}")

    def do_GET(self):
        if self.path == "/status":
            running = _tidevice_proc is not None and _tidevice_proc.poll() is None
            self._json(200, {"running": running, "bundle": TOUCH_BUNDLE})
        elif self.path == "/start":
            ok, msg = start_touch()
            self._json(200 if ok else 500, {"ok": ok, "msg": msg})
        elif self.path == "/stop":
            ok, msg = stop_touch()
            self._json(200, {"ok": ok, "msg": msg})
        else:
            self._json(404, {"error": "not found"})

    def _json(self, code: int, data: dict):
        import json
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(body))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)


# ── Touch control ─────────────────────────────────────────────────────────────

def start_touch() -> tuple[bool, str]:
    global _tidevice_proc
    with _lock:
        if _tidevice_proc and _tidevice_proc.poll() is None:
            return True, "Deja rulat"

        # Verifica daca tidevice e instalat
        if not shutil_which("tidevice"):
            return False, "tidevice nu e instalat. Ruleaza: pip3 install tidevice"

        try:
            _tidevice_proc = subprocess.Popen(
                ["tidevice", "xctest", "--bundle_id", TOUCH_BUNDLE],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
            )
            print(f"✅ TouchRunner pornit (PID {_tidevice_proc.pid})")
            return True, f"TouchRunner pornit (PID {_tidevice_proc.pid})"
        except Exception as e:
            return False, str(e)


def stop_touch() -> tuple[bool, str]:
    global _tidevice_proc
    with _lock:
        if _tidevice_proc and _tidevice_proc.poll() is None:
            _tidevice_proc.terminate()
            _tidevice_proc = None
            print("🛑 TouchRunner oprit")
            return True, "Oprit"
        return True, "Nu rula"


def shutil_which(cmd: str) -> bool:
    import shutil
    return shutil.which(cmd) is not None


# ── LaunchAgent (autostart la boot Mac) ────────────────────────────────────────

PLIST_NAME  = "com.aibot.macbridge"
SCRIPT_PATH = os.path.abspath(__file__)
PYTHON_PATH = sys.executable

PLIST_CONTENT = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{PLIST_NAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>{PYTHON_PATH}</string>
        <string>{SCRIPT_PATH}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/macbridge.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/macbridge.log</string>
</dict>
</plist>
"""


def install_launchagent():
    plist_dir  = os.path.expanduser("~/Library/LaunchAgents")
    plist_path = os.path.join(plist_dir, f"{PLIST_NAME}.plist")
    os.makedirs(plist_dir, exist_ok=True)
    with open(plist_path, "w") as f:
        f.write(PLIST_CONTENT)
    subprocess.run(["launchctl", "load", plist_path], check=True)
    print(f"✅ LaunchAgent instalat: {plist_path}")
    print("   Mac Bridge va porni automat la fiecare boot.")
    print(f"   Log: /tmp/macbridge.log")


def uninstall_launchagent():
    plist_path = os.path.expanduser(f"~/Library/LaunchAgents/{PLIST_NAME}.plist")
    if os.path.exists(plist_path):
        subprocess.run(["launchctl", "unload", plist_path])
        os.remove(plist_path)
        print("✅ LaunchAgent dezinstalat.")
    else:
        print("LaunchAgent nu era instalat.")


# ── Afiseaza IP-ul local ───────────────────────────────────────────────────────

def get_local_ip() -> str:
    import socket
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "localhost"


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Mac Bridge pentru BotBridge iPhone")
    parser.add_argument("--install-launchagent", action="store_true",
                        help="Instaleaza autostart la boot Mac")
    parser.add_argument("--uninstall-launchagent", action="store_true",
                        help="Dezinstaleaza autostart")
    parser.add_argument("--port", type=int, default=PORT)
    args = parser.parse_args()

    if args.install_launchagent:
        install_launchagent()
        return
    if args.uninstall_launchagent:
        uninstall_launchagent()
        return

    ip = get_local_ip()
    print(f"🖥  Mac Bridge pornit")
    print(f"   Local: http://localhost:{args.port}")
    print(f"   iPhone: http://{ip}:{args.port}")
    print(f"   Endpoints: /status  /start  /stop")
    print()

    # Oprire curata la CTRL+C
    def shutdown(sig, frame):
        stop_touch()
        print("\nMac Bridge oprit.")
        sys.exit(0)
    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    server = HTTPServer(("0.0.0.0", args.port), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
