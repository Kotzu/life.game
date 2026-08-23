"""Command-line interface: scan / classify / convert / export / validate /
build-manifest / report-coverage."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from . import scan as scan_mod
from . import classify as classify_mod
from . import convert as convert_mod
from . import manifest as manifest_mod
from . import validate as validate_mod
from . import reports as reports_mod
from . import reference as reference_mod
from .model import load_json


def _cfg(args) -> dict:
    cfg = load_json(Path(args.config), None)
    if cfg is None:
        raise SystemExit(f"config {args.config} not found — copy config.example.json")
    return cfg


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="mannequin_pipeline")
    p.add_argument("--config", default="config.json")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("scan")
    sub.add_parser("classify")
    conv = sub.add_parser("convert")
    conv.add_argument("--dry-run", action="store_true",
                      help="write job files without invoking Blender")
    sub.add_parser("export")
    sub.add_parser("validate")
    sub.add_parser("build-manifest")
    sub.add_parser("report-coverage")
    imp = sub.add_parser("import-reference",
                         help="build the reference catalog from a "
                              "pedComponentVariations_free.json dump")
    imp.add_argument("--dump", required=True)
    imp.add_argument("--commit", default="",
                     help="source repo commit hash, for provenance")
    sub.add_parser("crosscheck",
                   help="diff local scan against the reference catalog")
    args = p.parse_args(argv)

    cfg = _cfg(args)
    build_dir = Path(cfg.get("build_dir", "build"))
    manifest_path = Path(cfg["assets_resource_dir"]) / "mannequin_manifest.json"

    if args.cmd == "scan":
        out = scan_mod.scan(Path(cfg["extracted_dir"]), build_dir)
        print(json.dumps(out["counts"], indent=2))
    elif args.cmd == "classify":
        out = classify_mod.classify(build_dir, cfg)
        print(json.dumps(out["counts"], indent=2))
    elif args.cmd in ("convert", "export"):
        # `convert` builds mannequin-safe assets; `export` re-runs only jobs whose
        # exports are missing (same job runner — Sollumz exports in-script).
        jobs = convert_mod.build_jobs(build_dir, cfg)
        print(f"{len(jobs)} job(s) to run")
        out = convert_mod.run_jobs(build_dir, cfg, jobs,
                                   dry_run=getattr(args, "dry_run", False))
        print(json.dumps(out, indent=2))
        if out["failed"]:
            return 1
    elif args.cmd == "build-manifest":
        m = manifest_mod.build_manifest(build_dir, cfg, manifest_path)
        print(f"manifest v{m['version']} -> {manifest_path}")
    elif args.cmd == "validate":
        out = validate_mod.validate(build_dir, cfg, manifest_path)
        print(json.dumps(out, indent=2))
        if not out["ok"]:
            return 1
    elif args.cmd == "report-coverage":
        out = reports_mod.report(build_dir, cfg, manifest_path)
        print(f"coverage: {out['coverage_pct']}% -> coverage_report.md")
    elif args.cmd == "import-reference":
        ref = reference_mod.build_reference(Path(args.dump),
                                            source_commit=args.commit)
        for gender, g in ref["genders"].items():
            print(gender, json.dumps(g["totals"]))
    elif args.cmd == "crosscheck":
        out = reference_mod.crosscheck(build_dir)
        print(json.dumps(out["summary"], indent=2))
        if out["summary"]["missing"]:
            print("missing drawables listed in build/crosscheck_report.json")
            return 1
    return 0
