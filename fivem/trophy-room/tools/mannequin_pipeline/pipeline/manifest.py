"""build-manifest — produce mannequin_manifest.json with STABLE index allocation.

Stability contract: once a converted garment is allocated a local drawable index
inside the `mannequin` collection, that index is never reused or changed, even
if the source garment disappears. Allocation state lives inside the manifest
itself (`allocations`), making the manifest the single source of truth that
ships with kotzu_mannequin_assets.
"""

from __future__ import annotations

from pathlib import Path

from .convert import _alloc_mannequin_local
from .model import BODY_SKIN_COMPONENTS, load_json, save_json

MANIFEST_SCHEMA = "kotzu_mannequin_manifest/1"


def build_manifest(build_dir: Path, cfg: dict, manifest_path: Path) -> dict:
    catalog = load_json(build_dir / "scan_catalog.json")
    classification = load_json(build_dir / "classification.json")
    if not catalog or not classification:
        raise SystemExit("run `scan` and `classify` first")
    conversions = load_json(build_dir / "conversion_state.json", {"done": {}}) or {"done": {}}
    # THE index authority: the same allocator convert used when NAMING the
    # exported files — the manifest must mirror the files exactly
    alloc = load_json(build_dir / "manifest_alloc.json", {}) or {}

    manifest = load_json(manifest_path, None) or {
        "schema": MANIFEST_SCHEMA,
        "version": 0,
        "collection": cfg.get("collection_name", "mannequin"),
        "game_build": cfg.get("game_build"),
        "allocations": {"male": {}, "female": {}},
        "genders": {
            "male": {"body": {}, "garments": {}, "props": {}},
            "female": {"body": {}, "garments": {}, "props": {}},
        },
    }
    if manifest.get("schema") != MANIFEST_SCHEMA:
        raise SystemExit(f"manifest schema mismatch: {manifest.get('schema')}")

    manifest["version"] = int(manifest.get("version", 0)) + 1
    manifest["game_build"] = cfg.get("game_build")

    for key, rec in catalog["drawables"].items():
        cls = classification["items"].get(key)
        if not cls:
            continue
        gender = rec["gender"]
        g = manifest["genders"][gender]
        eff = cls["effective"]
        comp = str(rec["component_id"])

        if rec["is_prop"]:
            g["props"][key] = {"status": "pass_through" if eff == "skin_free" else eff}
            continue

        if eff == "body_skin":
            # body set: same index scheme as the exported file names — base
            # pieces keep their source index, DLC pieces use the shared alloc
            body = g["body"].setdefault(comp, {"variants": {}})
            src = f"{rec['collection']}:{rec['local_drawable']}"
            body["variants"][src] = _alloc_mannequin_local(alloc, rec)
        elif eff == "convert":
            entry = {
                "status": "converted" if key in conversions["done"] else "pending",
                "source": {
                    "collection": rec["collection"],
                    "drawable": rec["local_drawable"],
                    "textures": rec["texture_count"],
                },
            }
            if entry["status"] == "converted":
                entry["converted"] = {
                    "collection": manifest["collection"],
                    "drawable": _alloc_mannequin_local(alloc, rec),
                }
            g["garments"][key] = entry
        elif eff == "skin_free":
            g["garments"][key] = {"status": "skin_free"}
        elif eff == "incompatible":
            g["garments"][key] = {"status": "incompatible"}
        else:  # ambiguous
            g["garments"][key] = {"status": "pending_review"}

    manifest["allocations"] = alloc
    save_json(build_dir / "manifest_alloc.json", alloc)
    save_json(manifest_path, manifest)
    return manifest
