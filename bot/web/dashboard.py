"""
Web Dashboard - interfata web accesibila de pe orice dispozitiv (inclusiv iPhone).
Foloseste Flask + Flask-SocketIO pentru updates in timp real.

Acces: http://<ip-pc>:5000 din browserul iPhone (trebuie sa fie pe aceeasi retea WiFi)
"""

import base64
import io
import json
import threading
import time
from pathlib import Path
from typing import Optional

from flask import Flask, jsonify, render_template, request
from flask_socketio import SocketIO, emit

from utils.logger import log


app = Flask(__name__, template_folder="templates", static_folder="static")
app.config["SECRET_KEY"] = "bot-secret-key-2024"
socketio = SocketIO(app, cors_allowed_origins="*", async_mode="threading")

# Starea globala a botului (partajata intre thread-uri)
_bot_state = {
    "running": False,
    "game": None,
    "mode": "desktop",  # desktop | mobile
    "last_screenshot": None,  # base64 JPEG
    "last_action": None,
    "game_state": {},
    "stats": {
        "actions": 0,
        "errors": 0,
        "uptime": 0,
    },
    "kb_stats": {},
    "log_lines": [],  # ultimele 50 linii de log
}

_bot_thread: Optional[threading.Thread] = None
_start_time: Optional[float] = None

# Callback-uri din main (setate din exterior)
_start_callback = None
_stop_callback = None
_learn_callback = None


def set_callbacks(start_fn, stop_fn, learn_fn):
    """Seteaza callback-urile catre logica botului."""
    global _start_callback, _stop_callback, _learn_callback
    _start_callback = start_fn
    _stop_callback = stop_fn
    _learn_callback = learn_fn


def update_state(**kwargs):
    """Actualizeaza starea botului si notifica clientii web."""
    _bot_state.update(kwargs)
    # Trimite update la toti clientii conectati
    socketio.emit("state_update", {
        "running": _bot_state["running"],
        "game": _bot_state["game"],
        "mode": _bot_state["mode"],
        "last_action": _bot_state["last_action"],
        "game_state": _bot_state["game_state"],
        "stats": _bot_state["stats"],
    })


def push_screenshot(b64_jpeg: str):
    """Trimite screenshot nou la clientii web."""
    _bot_state["last_screenshot"] = b64_jpeg
    socketio.emit("screenshot", {"data": b64_jpeg})


def push_log(message: str, level: str = "info"):
    """Adauga o linie de log si o trimite la clientii web."""
    line = {"time": time.strftime("%H:%M:%S"), "level": level, "msg": message}
    _bot_state["log_lines"].append(line)
    if len(_bot_state["log_lines"]) > 100:
        _bot_state["log_lines"].pop(0)
    socketio.emit("log_line", line)


# ===== HTTP Routes =====

@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/state")
def api_state():
    """Starea curenta a botului (JSON)."""
    return jsonify({
        "running": _bot_state["running"],
        "game": _bot_state["game"],
        "mode": _bot_state["mode"],
        "last_action": _bot_state["last_action"],
        "game_state": _bot_state["game_state"],
        "stats": _bot_state["stats"],
        "kb_stats": _bot_state["kb_stats"],
        "uptime": int(time.time() - _start_time) if _start_time else 0,
    })


@app.route("/api/screenshot")
def api_screenshot():
    """Screenshot curent ca JSON base64."""
    return jsonify({"data": _bot_state.get("last_screenshot")})


@app.route("/api/start", methods=["POST"])
def api_start():
    """Porneste botul."""
    data = request.get_json() or {}
    game = data.get("game", "dota_underlords")
    mode = data.get("mode", "mobile")

    if _bot_state["running"]:
        return jsonify({"ok": False, "error": "Botul deja ruleaza"})

    if _start_callback:
        _start_callback(game=game, mode=mode)
        return jsonify({"ok": True})
    return jsonify({"ok": False, "error": "Start callback nesetat"})


@app.route("/api/stop", methods=["POST"])
def api_stop():
    """Opreste botul."""
    if _stop_callback:
        _stop_callback()
    return jsonify({"ok": True})


@app.route("/api/learn", methods=["POST"])
def api_learn():
    """Porneste invatarea din YouTube (search sau URL)."""
    data = request.get_json() or {}
    game = data.get("game", "dota_underlords")
    query = data.get("query", "")
    url = data.get("url", "")
    max_videos = int(data.get("max_videos", 3))

    if not query and not url:
        return jsonify({"ok": False, "error": "Trimite 'query' sau 'url'"})

    if _learn_callback:
        threading.Thread(
            target=_learn_callback,
            kwargs={"game": game, "query": query, "url": url, "max_videos": max_videos},
            daemon=True
        ).start()
        return jsonify({"ok": True, "message": "Invatarea a inceput in background"})

    return jsonify({"ok": False, "error": "Learn callback nesetat"})


@app.route("/api/logs")
def api_logs():
    """Ultimele linii de log."""
    return jsonify({"logs": _bot_state["log_lines"][-50:]})


@app.route("/api/kb_stats")
def api_kb_stats():
    """Statistici knowledge base."""
    return jsonify(_bot_state.get("kb_stats", {}))


# ===== WebSocket Events =====

@socketio.on("connect")
def on_connect():
    log.debug(f"Client web conectat: {request.sid}")
    # Trimite starea curenta la noul client
    emit("state_update", {
        "running": _bot_state["running"],
        "game": _bot_state["game"],
        "mode": _bot_state["mode"],
        "last_action": _bot_state["last_action"],
        "game_state": _bot_state["game_state"],
        "stats": _bot_state["stats"],
    })
    if _bot_state["last_screenshot"]:
        emit("screenshot", {"data": _bot_state["last_screenshot"]})
    # Trimite ultimele log-uri
    for line in _bot_state["log_lines"][-20:]:
        emit("log_line", line)


@socketio.on("disconnect")
def on_disconnect():
    log.debug(f"Client web deconectat: {request.sid}")


def run_dashboard(host: str = "0.0.0.0", port: int = 5000, debug: bool = False):
    """Porneste serverul web."""
    log.info(f"Dashboard pornit pe http://{host}:{port}")
    log.info("Acceseaza din iPhone: http://<IP-PC>:5000")
    socketio.run(app, host=host, port=port, debug=debug, use_reloader=False, log_output=False)
