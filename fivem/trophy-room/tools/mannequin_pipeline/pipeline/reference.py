"""Reference clothing catalog built from the open DurtyFree metadata dump
(github.com/DurtyFree/gta-v-data-dumps, pedComponentVariations_free.json).

Metadata only (names/IDs/counts) — no game assets. Purpose:

1. Pre-populate the §6 catalog denominators before any local extraction.
2. `crosscheck`: after `scan`, diff the local extraction against the reference
   to catch missing exports and game-build drift.
"""

from __future__ import annotations

from collections import defaultdict
from datetime import date
from pathlib import Path

from .model import load_json, save_json

REFERENCE_SCHEMA = "kotzu_freemode_reference/1"
DEFAULT_REFERENCE = Path(__file__).resolve().parent.parent / "reference" / \
    "freemode_reference_catalog.json"

PED_TO_GENDER = {"mp_m_freemode_01": "male", "mp_f_freemode_01": "female"}
GARMENT_COMPONENTS = {1, 4, 6, 8, 9, 10, 11}


def build_reference(dump_path: Path, out_path: Path = DEFAULT_REFERENCE,
                    source_commit: str = "") -> dict:
    dump = load_json(dump_path)
    if not isinstance(dump, list):
        raise SystemExit(f"unexpected dump format in {dump_path}")

    genders: dict[str, dict] = {}
    for entry in dump:
        gender = PED_TO_GENDER.get(entry.get("PedName", ""))
        if gender is None:
            continue
        g = genders.setdefault(gender, {"collections": {}, "totals": {
            "garment_drawables": 0, "body_drawables": 0, "prop_drawables": 0}})
        coll_name = entry["DlcCollectionName"]
        if coll_name == entry["PedName"]:
            coll_name = ""  # base collection is addressed as '' by the natives
        coll = g["collections"].setdefault(coll_name,
                                           {"components": {}, "props": {}})

        tex_sets: dict[tuple, set] = defaultdict(set)
        for v in entry.get("ComponentVariations") or []:
            tex_sets[("c", v["ComponentId"], v["RelativeCollectionDrawableId"])] \
                .add(v["TextureId"])
        for p in entry.get("Props") or []:
            tex_sets[("p", p["ComponentId"], p["RelativeCollectionDrawableId"])] \
                .add(p["TextureId"])

        for (kind, comp, local), texs in tex_sets.items():
            target = coll["components"] if kind == "c" else coll["props"]
            comp_map = target.setdefault(str(comp), {})
            comp_map[str(local)] = len(texs)
            if kind == "p":
                g["totals"]["prop_drawables"] += 1
            elif comp in GARMENT_COMPONENTS:
                g["totals"]["garment_drawables"] += 1
            else:
                g["totals"]["body_drawables"] += 1

    ref = {
        "schema": REFERENCE_SCHEMA,
        "source": {
            "repo": "DurtyFree/gta-v-data-dumps",
            "file": "pedComponentVariations_free.json",
            "commit": source_commit,
            "retrieved": date.today().isoformat(),
            "license_note": "aggregated metadata (IDs/counts) with attribution; "
                            "contains no game assets",
        },
        "genders": genders,
    }
    save_json(out_path, ref)
    return ref


def crosscheck(build_dir: Path, reference_path: Path = DEFAULT_REFERENCE) -> dict:
    catalog = load_json(build_dir / "scan_catalog.json")
    ref = load_json(reference_path)
    if not catalog:
        raise SystemExit("run `scan` first — build/scan_catalog.json missing")
    if not ref:
        raise SystemExit(f"reference catalog missing: {reference_path} "
                         "(run `import-reference --dump …`)")

    # index the local scan: (gender, kind, comp, collection, local) -> texture_count
    local = {}
    for rec in catalog["drawables"].values():
        kind = "p" if rec["is_prop"] else "c"
        key = (rec["gender"], kind, rec["component_id"], rec["collection"],
               rec["local_drawable"])
        local[key] = rec["texture_count"]

    missing = []          # in reference, not extracted locally
    unknown = []          # extracted locally, not in reference (addon or drift)
    texture_mismatch = []
    matched = 0

    ref_keys = set()
    for gender, g in ref["genders"].items():
        for coll_name, coll in g["collections"].items():
            for kind, section in (("c", coll["components"]), ("p", coll["props"])):
                for comp, drawables in section.items():
                    for local_idx, tex_count in drawables.items():
                        key = (gender, kind, int(comp), coll_name, int(local_idx))
                        ref_keys.add(key)
                        if key not in local:
                            missing.append(_fmt(key))
                        else:
                            matched += 1
                            if local[key] and tex_count and local[key] != tex_count:
                                texture_mismatch.append(
                                    f"{_fmt(key)} local={local[key]} ref={tex_count}")

    for key in local:
        if key not in ref_keys:
            unknown.append(_fmt(key))

    report = {
        "schema": "kotzu_crosscheck/1",
        "reference": ref["source"],
        "matched": matched,
        "missing_locally": sorted(missing),
        "unknown_locally": sorted(unknown),
        "texture_mismatches": sorted(texture_mismatch),
        "summary": {
            "matched": matched,
            "missing": len(missing),
            "unknown": len(unknown),
            "texture_mismatches": len(texture_mismatch),
        },
    }
    save_json(build_dir / "crosscheck_report.json", report)
    return report


def _fmt(key) -> str:
    gender, kind, comp, coll, local_idx = key
    return f"{gender}:{'prop' if kind == 'p' else 'comp'}{comp}:{coll}:{local_idx}"
