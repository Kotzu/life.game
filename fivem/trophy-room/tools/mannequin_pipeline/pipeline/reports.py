"""report-coverage — emit conversion_report.json + coverage_report.md."""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from .model import COMPONENT_IDS, load_json, save_json


def report(build_dir: Path, cfg: dict, manifest_path: Path) -> dict:
    manifest = load_json(manifest_path, None)
    classification = load_json(build_dir / "classification.json", None)
    if not manifest or not classification:
        raise SystemExit("run classify + build-manifest first")

    rows = []
    totals = {"total": 0, "supported": 0, "pending": 0, "incompatible": 0, "review": 0}
    per_gender: dict[str, dict] = {}

    for gender in ("male", "female"):
        g = manifest["genders"][gender]
        gt = per_gender.setdefault(
            gender,
            {"total": 0, "supported": 0, "pending": 0, "incompatible": 0, "review": 0})
        for key, entry in sorted(g["garments"].items()):
            status = entry["status"]
            totals["total"] += 1
            gt["total"] += 1
            if status in ("skin_free", "converted"):
                totals["supported"] += 1
                gt["supported"] += 1
            elif status == "pending":
                totals["pending"] += 1
                gt["pending"] += 1
            elif status == "pending_review":
                totals["review"] += 1
                gt["review"] += 1
            else:
                totals["incompatible"] += 1
                gt["incompatible"] += 1
            rows.append({"key": key, "gender": gender, **entry})
        # body completeness counts as a hard gate, reported separately
        gt["body_components_present"] = sorted(g["body"].keys())

    coverage_pct = (100.0 * totals["supported"] / totals["total"]) if totals["total"] else 0.0
    conv = {
        "schema": "kotzu_conversion_report/1",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "game_build": manifest.get("game_build"),
        "manifest_version": manifest.get("version"),
        "totals": totals,
        "coverage_pct": round(coverage_pct, 2),
        "per_gender": per_gender,
        "items": rows,
    }
    save_json(Path("conversion_report.json"), conv)

    md = [
        "# Default Clothing Coverage Report",
        "",
        f"Generated: {conv['generated_at']} · game build {conv['game_build']} · "
        f"manifest v{conv['manifest_version']}",
        "",
        f"## Coverage: **{conv['coverage_pct']}%** "
        f"({totals['supported']}/{totals['total']} garment drawables render skin-free)",
        "",
        "| Gender | Total | Supported | Pending conversion | Manual review | Incompatible |",
        "|---|---|---|---|---|---|",
    ]
    for gender, gt in per_gender.items():
        md.append(f"| {gender} | {gt['total']} | {gt['supported']} | {gt['pending']} | "
                  f"{gt['review']} | {gt['incompatible']} |")
    md += [
        "",
        "Body set present per gender (component IDs): "
        + "; ".join(f"{g}: {', '.join(COMPONENT_IDS.get(int(c), c) for c in gt['body_components_present']) or 'NONE'}"
                    for g, gt in per_gender.items()),
        "",
        "## Interpretation rules (acceptance §6)",
        "- A garment counts as *supported* only when `skin_free` (verified) or `converted`.",
        "- `pending`, `pending_review`, `incompatible` garments are refused in game with an",
        "  explicit incompatible state — they never render human skin.",
        "- \"All default clothing supported\" may only be claimed when Supported == Total",
        "  for both genders on the server's game build.",
    ]
    Path("coverage_report.md").write_text("\n".join(md) + "\n", encoding="utf-8")
    return conv
