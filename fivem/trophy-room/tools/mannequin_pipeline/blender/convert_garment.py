"""Convert one skin-bearing garment drawable into its mannequin-safe twin.

Invoked headlessly:
  blender --background --factory-startup --addons sollumz \
      --python convert_garment.py -- --job build/jobs/<hash>.json --out <result.json>

Contract with pipeline/convert.py:
  result.status: ok | ambiguous | failed
  - 'ambiguous' means a material could not be confidently classified as
    skin/garment. The item goes to manual_review_queue.json; we NEVER guess.

Preserves: skeleton/armature, vertex groups & weights, UVs, custom normals,
LOD hierarchy (Sollumz keeps LOD meshes as separate mesh data on import),
garment materials/textures. Only skin materials are swapped.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from material_mannequin import replace_skin_materials  # noqa: E402


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--job", required=True)
    ap.add_argument("--out", required=True)
    return ap.parse_args(argv)


def write_result(out_path: str, payload: dict) -> None:
    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    Path(out_path).write_text(json.dumps(payload, indent=2), encoding="utf-8")


def sollumz_import(path: str) -> None:
    """Sollumz import with operator-id compatibility across versions."""
    p = Path(path)
    candidates = (
        lambda: bpy.ops.sollumz.import_assets(directory=str(p.parent),
                                              files=[{"name": p.name}]),
        lambda: bpy.ops.sollumz.importydd(filepath=str(p)),
        lambda: bpy.ops.import_scene.ydd(filepath=str(p)),
    )
    errors = []
    for fn in candidates:
        try:
            fn()
            return
        except Exception as e:  # noqa: BLE001 - collect and continue
            errors.append(str(e))
    raise RuntimeError("no Sollumz import operator worked: " + " | ".join(errors))


def _select_all_for_export() -> None:
    """Sollumz's export operates on the selection; in --background nothing is
    selected by default, and the operator then 'succeeds' without writing."""
    for obj in bpy.data.objects:
        try:
            obj.select_set(True)
        except Exception:  # noqa: BLE001 - object not in view layer
            pass
    try:
        roots = [o for o in bpy.data.objects if o.parent is None]
        if roots:
            bpy.context.view_layer.objects.active = roots[0]
    except Exception:  # noqa: BLE001
        pass


def sollumz_export(out_dir: str) -> list[str]:
    """Export the scene's assets and PROVE files were written — an operator
    returning FINISHED with an empty directory is a failure, never success."""
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    # recursive: Sollumz writes into generation subfolders (e.g. stream/gen8/);
    # snapshot (path, mtime, size) so an overwrite of an existing file from a
    # previous run still counts as written
    def _files():
        return {(str(f.relative_to(out)), f.stat().st_mtime_ns, f.stat().st_size)
                for f in out.rglob("*") if f.is_file()}
    before = _files()
    _select_all_for_export()
    candidates = (
        # verified against Sollumz 2.9: export_assets(directory, direct_export)
        lambda: bpy.ops.sollumz.export_assets(directory=out_dir, direct_export=True),
        lambda: bpy.ops.sollumz.export_assets(directory=out_dir),
        lambda: bpy.ops.sollumz.exportydd(directory=out_dir),
    )
    errors = []
    for fn in candidates:
        try:
            fn()
        except Exception as e:  # noqa: BLE001
            errors.append(str(e))
            continue
        written = sorted({path for path, _, _ in _files() - before})
        if written:
            return written
        errors.append("operator finished but wrote no files")
    raise RuntimeError("no Sollumz export operator produced files: "
                       + " | ".join(errors))


def target_name(job: dict, mannequin_local: int | None = None) -> str:
    """Converted assets are named into the mannequin DLC collection:
    mp_m_freemode_01_<collection_name>^<slug>_<idx>_u
    The local index is finalized by build-manifest; at convert time we keep the
    source index inside the file name of the job output and let export renaming
    (validate step) reconcile against the manifest allocation."""
    model = "mp_m_freemode_01" if job["gender"] == "male" else "mp_f_freemode_01"
    idx = mannequin_local if mannequin_local is not None else job["local_drawable"]
    return f"{model}_{job['collection_name']}^{job['component_slug']}_{idx:03d}_u"


def main() -> None:
    args = parse_args()
    job = json.loads(Path(args.job).read_text(encoding="utf-8"))

    try:
        sollumz_import(job["source"])
    except Exception as e:  # noqa: BLE001
        write_result(args.out, {"status": "failed", "reason": f"import: {e}"})
        return

    replaced, kept, unknown = [], [], []
    mesh_objs = [o for o in bpy.data.objects if o.type == "MESH"]
    if not mesh_objs:
        write_result(args.out, {"status": "failed", "reason": "no meshes imported"})
        return

    for obj in mesh_objs:
        r = replace_skin_materials(obj, hints=job.get("hints"))
        replaced += r["replaced"]
        kept += r["kept"]
        unknown += r["unknown"]

    if unknown:
        write_result(args.out, {
            "status": "ambiguous",
            "reason": "materials could not be classified",
            "evidence": {"unknown": unknown, "replaced": replaced, "kept": kept},
        })
        return
    if not replaced and job["kind"] == "garment":
        # classified 'convert' but no skin material found — needs a human eye
        write_result(args.out, {
            "status": "ambiguous",
            "reason": "classifier said convert, but no skin material matched in Blender",
            "evidence": {"kept": kept},
        })
        return

    new_name = target_name(job)
    for obj in bpy.data.objects:
        if obj.parent is None and obj.type in ("ARMATURE", "EMPTY", "MESH"):
            obj.name = new_name

    try:
        written = sollumz_export(job["out_dir"])
    except Exception as e:  # noqa: BLE001
        write_result(args.out, {"status": "failed", "reason": f"export: {e}"})
        return

    write_result(args.out, {
        "status": "ok",
        "output_name": new_name,
        "files": written,
        "replaced": replaced,
        "kept": kept,
    })


if __name__ == "__main__":
    main()
