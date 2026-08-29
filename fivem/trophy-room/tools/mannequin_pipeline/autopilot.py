"""AUTOPILOT — hands-free iteration loop between this workstation and Claude.

Start it ONCE and leave the window open:

    python autopilot.py

It then, forever:
  1. watches the git branch for new commits from Claude,
  2. when one arrives: pulls and runs `make_reports.py --convert --preview`
     (which pushes the resulting reports/previews back to Claude),
  3. if a run crashes, the error is committed and pushed so Claude can fix it.

Stop it with Ctrl+C, or by creating a file named STOP_AUTOPILOT next to it.
"""

from __future__ import annotations

import subprocess
import sys
import time
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent
BRANCH = "claude/fivem-trophy-mannequin-d5lwja"
STOP = HERE / "STOP_AUTOPILOT"
POLL_SECONDS = 60


def sh(*cmd: str, **kw) -> subprocess.CompletedProcess:
    print("  $", " ".join(cmd), flush=True)
    return subprocess.run(list(cmd), cwd=str(HERE), **kw)


def remote_head() -> str:
    sh("git", "fetch", "origin", BRANCH, capture_output=True)
    r = subprocess.run(["git", "rev-parse", f"origin/{BRANCH}"],
                       cwd=str(HERE), capture_output=True, text=True)
    return r.stdout.strip()


def push_error_report() -> None:
    err = HERE / "build" / "autopilot_error.txt"
    err.parent.mkdir(exist_ok=True)
    err.write_text(traceback.format_exc(), encoding="utf-8")
    sh("git", "add", "-f", "build/autopilot_error.txt")
    sh("git", "commit", "-m", "autopilot: run failed, error attached")
    sh("git", "pull", "--no-rebase", "--no-edit")
    sh("git", "push", "-u", "origin", BRANCH)


def run_once() -> None:
    try:
        r = sh(sys.executable, "make_reports.py", "--convert", "--preview")
        if r.returncode != 0:
            raise RuntimeError(f"make_reports exited with {r.returncode}")
    except Exception:  # noqa: BLE001 — ship the error to Claude, keep looping
        print("AUTOPILOT: run failed — pushing the error for Claude", flush=True)
        push_error_report()


def main() -> None:
    print("AUTOPILOT pornit. Lasa fereastra deschisa; totul merge singur.")
    print("Oprire: Ctrl+C sau creeaza fisierul STOP_AUTOPILOT.\n", flush=True)
    processed = ""
    first = True
    while not STOP.exists():
        head = remote_head()
        if first or (head and head != processed):
            print(f"\nAUTOPILOT: modificari noi ({head[:9]}) — rulez.", flush=True)
            sh("git", "pull", "--no-rebase", "--no-edit")
            run_once()
            processed = remote_head()
            first = False
            print("\nAUTOPILOT: gata; astept urmatoarele modificari de la Claude...",
                  flush=True)
        time.sleep(POLL_SECONDS)
    print("AUTOPILOT oprit (STOP_AUTOPILOT).")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nAUTOPILOT oprit.")
