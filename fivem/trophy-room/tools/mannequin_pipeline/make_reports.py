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
           "build/classification.json", "manual_review_queue.json",
           "build/conversion_state.json"]


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


def find_blender() -> None:
    """Make sure config.json's blender_exe points at a real blender.exe."""
    step("locating Blender")
    cfg_path = HERE / "config.json"
    cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
    exe = Path(cfg.get("blender_exe", ""))
    if exe.is_file():
        print("  blender_exe OK:", exe)
        return
    candidates = sorted(Path("C:/Program Files/Blender Foundation").glob(
        "Blender */blender.exe")) if Path("C:/Program Files/Blender Foundation").exists() else []
    if not candidates:
        raise SystemExit(
            "! Blender not found. Install Blender 4.2 LTS (blender.org), or set "
            "\"blender_exe\" in config.json to your blender.exe path, then rerun.")
    cfg["blender_exe"] = candidates[-1].as_posix()
    cfg_path.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
    print("  blender_exe ->", cfg["blender_exe"])


def _stream_dir(cfg: dict) -> Path:
    stream = Path(cfg["assets_resource_dir"]) / "stream"
    return stream if stream.is_absolute() else (HERE / stream).resolve()


def reset_state_if_stream_empty() -> None:
    """Self-heal: if conversion_state claims work is done but the stream dir
    holds no assets (the silent-export bug), re-run everything."""
    state_p = HERE / "build" / "conversion_state.json"
    if not state_p.exists():
        return
    st = json.loads(state_p.read_text(encoding="utf-8"))
    if not st.get("done"):
        return
    cfg = json.loads((HERE / "config.json").read_text(encoding="utf-8"))
    stream = _stream_dir(cfg)
    if stream.is_dir() and any(stream.rglob("*.ydd*")):
        return
    print("  ! state says converted but the stream dir is empty — "
          "resetting conversion state to re-run all jobs")
    state_p.unlink()


def run_convert() -> None:
    find_blender()
    reset_state_if_stream_empty()
    step("pipeline convert (Blender, headless — this takes a while; "
         "progress prints per item)")
    run([sys.executable, "-m", "pipeline", "convert"])
    st = json.loads((HERE / "build/conversion_state.json").read_text(encoding="utf-8"))
    print(f"\n  converted so far: {len(st.get('done', {}))}  "
          f"failed: {len(st.get('failed', {}))}")


def run_preview() -> None:
    """Render the assembled mannequin (front + 3/4, both genders) to PNGs."""
    find_blender()
    sys.path.insert(0, str(HERE))
    from pipeline.convert import SOLLUMZ_ADDONS
    cfg = json.loads((HERE / "config.json").read_text(encoding="utf-8"))
    stream = Path(cfg["assets_resource_dir"]) / "stream"
    if not stream.is_absolute():
        stream = (HERE / stream).resolve()
    out_dir = HERE / "build" / "previews"
    step("rendering assembled mannequin previews")
    for gender in ("male", "female"):
        run([cfg["blender_exe"], "--background",
             "--addons", SOLLUMZ_ADDONS,
             "--python", str(HERE / "blender" / "render_mannequin.py"), "--",
             "--stream", str(stream), "--gender", gender,
             "--out-dir", str(out_dir),
             "--result", str(out_dir / f"{gender}.result.json")])
        res_path = out_dir / f"{gender}.result.json"
        res = json.loads(res_path.read_text(encoding="utf-8")) if res_path.exists() else {}
        print(f"  {gender}: {res.get('status', 'no result')} "
              f"{res.get('renders', res.get('reason', ''))}")

    step("rendering per-piece identification sheets (uppr/lowr/feet/jbib)")
    for gender in ("male", "female"):
        run([cfg["blender_exe"], "--background",
             "--addons", SOLLUMZ_ADDONS,
             "--python", str(HERE / "blender" / "render_mannequin.py"), "--",
             "--stream", str(stream), "--gender", gender,
             "--out-dir", str(out_dir),
             "--sheet", "uppr,lowr,feet,jbib,accs",
             "--result", str(out_dir / f"{gender}.sheets.result.json")])
        res_path = out_dir / f"{gender}.sheets.result.json"
        res = json.loads(res_path.read_text(encoding="utf-8")) if res_path.exists() else {}
        print(f"  {gender} sheets: {res.get('status')} "
              f"({len(res.get('renders', []))} renders)")


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
    to_add = list(REPORTS)
    previews = HERE / "build" / "previews"
    if previews.is_dir():
        to_add += [str(p.relative_to(HERE)).replace("\\", "/")
                   for p in sorted(previews.rglob("*"))
                   if p.suffix in (".png", ".json")]
    for rel in to_add:
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
    ap.add_argument("--convert", action="store_true",
                    help="also run the Blender conversion step after classify")
    ap.add_argument("--preview", action="store_true",
                    help="also render assembled-mannequin preview PNGs")
    args = ap.parse_args()

    extracted = Path(args.extracted)
    normalize_folders(extracted)
    ensure_pillow()
    write_config(extracted)
    run_pipeline()
    if args.convert:
        run_convert()
    if args.preview:
        run_preview()
    summarize()
    if not args.no_git:
        push_reports()


if __name__ == "__main__":
    main()
