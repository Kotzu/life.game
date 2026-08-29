"""convert / export — build Blender jobs for skin-bearing garments and the
mannequin body set, run them headlessly, and track completion incrementally.

A job is a JSON file consumed by blender/convert_garment.py (or
build_mannequin_body.py) running inside `blender --background`. Jobs that fail
or that the Blender script flags as ambiguous land back in the manual review
queue — nothing is silently guessed.
"""

from __future__ import annotations

import hashlib
import subprocess
from pathlib import Path

from .model import load_json, save_json

BLENDER_DIR = Path(__file__).resolve().parent.parent / "blender"


def _job_hash(rec: dict) -> str:
    ident = f"{rec['source_path']}|{rec['texture_count']}"
    return hashlib.sha256(ident.encode()).hexdigest()[:16]


def build_jobs(build_dir: Path, cfg: dict) -> list[dict]:
    catalog = load_json(build_dir / "scan_catalog.json")
    classification = load_json(build_dir / "classification.json")
    if not catalog or not classification:
        raise SystemExit("run `scan` and `classify` first")
    state = load_json(build_dir / "conversion_state.json", {"done": {}}) or {"done": {}}

    jobs = []
    for key, rec in catalog["drawables"].items():
        cls = classification["items"].get(key)
        if not cls:
            continue
        eff = cls["effective"]
        if eff not in ("convert", "body_skin"):
            continue
        h = _job_hash(rec)
        if state["done"].get(key) == h:
            continue  # incremental: unchanged input already converted
        jobs.append({
            "key": key,
            "kind": "body" if eff == "body_skin" else "garment",
            "hash": h,
            "source": rec["source_path"],
            "gender": rec["gender"],
            "component_id": rec["component_id"],
            "component_slug": rec["component_slug"],
            "collection": rec["collection"],
            "local_drawable": rec["local_drawable"],
            "textures": rec["texture_names"],
            "collection_name": cfg.get("collection_name", "mannequin"),
            "out_dir": str(Path(cfg["assets_resource_dir"]) / "stream"),
        })
    return jobs


def run_jobs(build_dir: Path, cfg: dict, jobs: list[dict],
             dry_run: bool = False) -> dict:
    state = load_json(build_dir / "conversion_state.json", {"done": {}, "failed": {}}) \
        or {"done": {}, "failed": {}}
    state.setdefault("failed", {})
    blender = cfg.get("blender_exe", "blender")
    results = {"ok": 0, "failed": 0, "ambiguous": 0, "dry_run": dry_run}
    # Sollumz's module name depends on how it was installed: legacy addon zip
    # ('Sollumz'/'sollumz') or a Blender 4.2 extension (bl_ext.<repo>.sollumz).
    # --addons takes a comma list and only warns about unknown names, so enable
    # every candidate; user preferences load too (no --factory-startup), which
    # covers an already-enabled install regardless of its name.
    addon_candidates = ",".join((
        "sollumz", "Sollumz",
        "bl_ext.user_default.sollumz", "bl_ext.user_default.Sollumz",
        "bl_ext.blender_org.sollumz",
    ))

    for i, job in enumerate(jobs, 1):
        job_path = build_dir / "jobs" / f"{job['hash']}.json"
        save_json(job_path, job)
        result_path = build_dir / "jobs" / f"{job['hash']}.result.json"
        if dry_run:
            continue
        script = BLENDER_DIR / ("build_mannequin_body.py" if job["kind"] == "body"
                                else "convert_garment.py")
        cmd = [blender, "--background",
               "--addons", addon_candidates,
               "--python", str(script), "--",
               "--job", str(job_path), "--out", str(result_path)]
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
            res = load_json(result_path, None)
            if proc.returncode == 0 and res and res.get("status") == "ok":
                state["done"][job["key"]] = job["hash"]
                state["failed"].pop(job["key"], None)
                results["ok"] += 1
                status = "ok"
            elif res and res.get("status") == "ambiguous":
                results["ambiguous"] += 1
                _queue_ambiguous(job, res)
                status = "ambiguous"
            else:
                results["failed"] += 1
                state["failed"][job["key"]] = {
                    "hash": job["hash"],
                    "rc": proc.returncode,
                    "reason": (res or {}).get("reason"),
                    "stderr_tail": proc.stderr[-2000:],
                }
                status = "FAILED"
        except (subprocess.TimeoutExpired, FileNotFoundError) as e:
            results["failed"] += 1
            state["failed"][job["key"]] = {"hash": job["hash"], "error": str(e)}
            status = "FAILED (" + type(e).__name__ + ")"
        print(f"  [{i}/{len(jobs)}] {job['key']} ({job['kind']}) -> {status}",
              flush=True)
        # persist incrementally so an interrupted run loses nothing
        save_json(build_dir / "conversion_state.json", state)

    save_json(build_dir / "conversion_state.json", state)
    return results


def _queue_ambiguous(job: dict, res: dict) -> None:
    queue_path = Path("manual_review_queue.json")
    queue = load_json(queue_path, {"items": []}) or {"items": []}
    items = queue.get("items", [])
    if any(i.get("key") == job["key"] and not i.get("resolution") for i in items):
        return
    items.append({
        "key": job["key"],
        "reason": "blender conversion flagged ambiguity: " + res.get("reason", "?"),
        "evidence": res.get("evidence", {}),
        "resolution": None,
    })
    queue["items"] = items
    queue["unresolved"] = sum(1 for i in items if not i.get("resolution"))
    save_json(queue_path, queue)
