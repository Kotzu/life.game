"""validate — sanity-check exported assets and manifest consistency."""

from __future__ import annotations

from pathlib import Path

from .model import load_json, save_json

MAX_YDD_MB = 16
MAX_YTD_MB = 32


def validate(build_dir: Path, cfg: dict, manifest_path: Path) -> dict:
    problems: list[str] = []
    warnings: list[str] = []

    manifest = load_json(manifest_path, None)
    if manifest is None:
        problems.append("mannequin_manifest.json missing — run build-manifest")
    else:
        for gender in ("male", "female"):
            body = manifest["genders"][gender]["body"]
            # must match the runtime contract: client ApplyBase hard-requires
            # 0/2/3/5 (head/hair/uppr/hand) and uses 4/6 for the bare base
            for comp in ("0", "2", "3", "4", "5", "6"):
                if comp not in body:
                    problems.append(
                        f"{gender}: mannequin body missing component {comp} — "
                        "run convert/export for the body set")
            # allocation uniqueness per component
            for comp, allocs in manifest["allocations"][gender].items():
                vals = list(allocs.values())
                if len(vals) != len(set(vals)):
                    problems.append(f"{gender} comp {comp}: duplicate local indexes in allocation")

    stream = Path(cfg["assets_resource_dir"]) / "stream"
    if not stream.exists():
        warnings.append(f"stream dir {stream} not found (expected on workstation only)")
    else:
        for f in stream.rglob("*"):
            if not f.is_file():
                continue
            mb = f.stat().st_size / (1024 * 1024)
            if f.suffix == ".ydd" and mb > MAX_YDD_MB:
                warnings.append(f"{f.name}: {mb:.1f} MB exceeds {MAX_YDD_MB} MB budget")
            if f.suffix == ".ytd" and mb > MAX_YTD_MB:
                warnings.append(f"{f.name}: {mb:.1f} MB exceeds {MAX_YTD_MB} MB budget")

    state = load_json(build_dir / "conversion_state.json", {"done": {}, "failed": {}}) or {}
    for key, info in (state.get("failed") or {}).items():
        problems.append(f"conversion failed for {key}: {info}")

    queue = load_json(Path("manual_review_queue.json"), {"items": []}) or {}
    unresolved = [i for i in queue.get("items", []) if not i.get("resolution")]
    if unresolved:
        warnings.append(f"{len(unresolved)} item(s) awaiting manual review — "
                        "these render as 'incompatible' in game until resolved")

    report = {
        "schema": "kotzu_validate/1",
        "ok": not problems,
        "problems": problems,
        "warnings": warnings,
    }
    save_json(build_dir / "validate_report.json", report)
    return report
