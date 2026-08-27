"""One-command workstation step: extraction folder -> pushed metadata reports.

Runs ON THE WORKSTATION (the extracted CodeWalker files never leave it):

    python make_reports.py [--extracted <dir>] [--no-git]

What it does, in order:
  1. normalizes the extraction folder names (Male -> mp_m_freemode_01 etc. —
     the scanner derives identity from the parent folder name),
  2. makes sure Pillow is installed (DDS/PNG skin-pixel analysis),
  3. writes config.json pointing at the extraction folder,
  4. runs `pipeline scan`, `pipeline crosscheck`, `pipeline classify`,
  5. prints a human summary of coverage,
  6. commits & pushes ONLY the metadata JSON reports (never game assets).
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_EXTRACTED = r"D:\Downloads\1cfcd8-CodeWalker30_dev46\CodeWalker30_dev46\_Manequin"
BRANCH = "claude/fivem-trophy-mannequin-d5lwja"

# friendly folder name -> canonical RPF folder name
RENAMES = {
    "male": "mp_m_freemode_01",
    "male_p": "mp_m_freemode_01_p",
    "male_props": "mp_m_freemode_01_p",
    "female": "mp_f_freemode_01",
    "female_p": "mp_f_freemode_01_p",
    "female_props": "mp_f_freemode_01_p",
}

REPORTS = ["build/scan_catalog.json", "build/crosscheck_report.json",
           "build/classification.json", "manual_review_queue.json"]


def step(msg: str) -> None:
    print(f"\n=== {msg}")


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    print("  $", " ".join(str(c) for c in cmd))
    return subprocess.run(cmd, cwd=str(HERE), **kw)


def normalize_folders(extracted: Path) -> None:
    step("normalizing folder names")
    if not extracted.is_dir():
        raise SystemExit(f"extraction folder not found: {extracted}")
    for child in sorted(extracted.iterdir()):
        if not child.is_dir():
            continue
        want = RENAMES.get(child.name.lower())
        if want and child.name != want:
            target = extracted / want
            if target.exists():
                print(f"  ! both {child.name} and {want} exist — merge manually")
                continue
            try:
                child.rename(target)
            except PermissionError:
                raise SystemExit(
                    f"\n! Cannot rename '{child.name}' -> '{want}': the folder is "
                    "locked by another program.\n"
                    "  Close CodeWalker and any Explorer window open on that "
                    "folder, then run this script again.\n"
                    f"  (Or rename it yourself in Explorer to exactly: {want})")
            print(f"  renamed {child.name} -> {want}")
    found = [c.name for c in sorted(extracted.iterdir())
             if c.is_dir() and c.name.lower().startswith(("mp_m_", "mp_f_"))]
    if not found:
        raise SystemExit(
            "no mp_m_/mp_f_ folders found in the extraction dir — export the "
            "RPF folders first (see EXTRACTION_LIST.md)")
    print("  ped folders:", ", ".join(found))


def ensure_pillow() -> None:
    step("checking Pillow (texture analysis)")
    try:
        import PIL  # noqa: F401
        print("  Pillow OK")
    except ImportError:
        print("  installing Pillow ...")
        r = run([sys.executable, "-m", "pip", "install", "--user", "pillow"])
        if r.returncode != 0:
            print("  ! Pillow install failed — classification will queue more "
                  "items for manual review, continuing anyway")


def write_config(extracted: Path) -> None:
    step("writing config.json")
    cfg = json.loads((HERE / "config.example.json").read_text(encoding="utf-8"))
    existing = HERE / "config.json"
    if existing.exists():
        cfg.update(json.loads(existing.read_text(encoding="utf-8")))
    cfg["extracted_dir"] = extracted.as_posix()
    existing.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
    print("  extracted_dir =", cfg["extracted_dir"])


def run_pipeline() -> None:
    for cmd in ("scan", "crosscheck", "classify"):
        step(f"pipeline {cmd}")
        r = run([sys.executable, "-m", "pipeline", cmd])
        if r.returncode != 0 and cmd != "crosscheck":  # crosscheck exits 1 on gaps
            raise SystemExit(f"pipeline {cmd} failed — fix the error above and rerun")


def summarize() -> None:
    step("summary")
    scan = json.loads((HERE / "build/scan_catalog.json").read_text(encoding="utf-8"))
    print(f"  drawables scanned: {scan['counts']['drawables']} "
          f"(skipped files: {scan['counts']['skipped']})")
    cc_path = HERE / "build/crosscheck_report.json"
    if cc_path.exists():
        cc = json.loads(cc_path.read_text(encoding="utf-8"))
        for k in ("missing_locally", "unknown_locally"):
            v = cc.get(k)
            if isinstance(v, list):
                print(f"  crosscheck {k}: {len(v)}")
    cls_path = HERE / "build/classification.json"
    if cls_path.exists():
        cls = json.loads(cls_path.read_text(encoding="utf-8"))
        counts: dict[str, int] = {}
        for c in cls.get("items", {}).values():
            eff = c.get("effective") or c.get("category", "?")
            counts[eff] = counts.get(eff, 0) + 1
        print("  classification:", ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))
        amb = counts.get("ambiguous", 0)
        if amb:
            print(f"  -> {amb} item(s) need manual review (manual_review_queue.json)")


def push_reports() -> None:
    step("committing metadata reports")
    br = run(["git", "rev-parse", "--abbrev-ref", "HEAD"],
             capture_output=True, text=True).stdout.strip()
    if br != BRANCH:
        print(f"  ! current branch is '{br}', expected '{BRANCH}' — "
              f"run: git checkout {BRANCH}")
        raise SystemExit(1)
    for rel in REPORTS:
        if (HERE / rel).exists():
            run(["git", "add", "-f", rel])
    diff = run(["git", "diff", "--cached", "--quiet"])
    if diff.returncode == 0:
        print("  nothing new to commit (reports unchanged)")
        return
    run(["git", "commit", "-m", "pipeline: scan+crosscheck+classify reports from workstation"])
    # bring in any commits pushed remotely in the meantime, else push is rejected
    run(["git", "pull", "--no-rebase", "--no-edit"])
    for attempt in range(4):
        if run(["git", "push", "-u", "origin", BRANCH]).returncode == 0:
            print("\nDONE — reports pushed. Tell Claude to analyze them.")
            return
        import time
        time.sleep(2 ** (attempt + 1))
    print("  ! push failed — run 'git push -u origin " + BRANCH + "' manually")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--extracted", default=DEFAULT_EXTRACTED,
                    help="CodeWalker export folder (default: %(default)s)")
    ap.add_argument("--no-git", action="store_true",
                    help="run everything but skip commit/push")
    args = ap.parse_args()

    extracted = Path(args.extracted)
    normalize_folders(extracted)
    ensure_pillow()
    write_config(extracted)
    run_pipeline()
    summarize()
    if not args.no_git:
        push_reports()


if __name__ == "__main__":
    main()
