"""Render the ASSEMBLED mannequin (converted body pieces worn together).

  blender --background --addons <sollumz-candidates> \
      --python render_mannequin.py -- --stream <dir> --gender male \
      --out-dir build/previews --result build/previews/male.result.json

Imports the mannequin base body set (head/uppr/lowr/feet/hand + scalp) from the
produced stream assets — ped component meshes share the same model space, so
importing them together yields the assembled figure — then renders front and
three-quarter views. Pipeline QA only, NOT FiveM acceptance evidence.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from convert_garment import sollumz_import, write_result  # noqa: E402

PIECE_SLUGS = ("head", "hair", "uppr", "lowr", "hand", "feet")


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--stream", required=True)
    ap.add_argument("--gender", required=True, choices=("male", "female"))
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--result", required=True)
    return ap.parse_args(argv)


def find_pieces(stream: Path, gender: str) -> list[Path]:
    model = "mp_m_freemode_01" if gender == "male" else "mp_f_freemode_01"
    all_assets = sorted(p for p in stream.rglob("*")
                        if p.is_file() and ".ydd" in p.name.lower()
                        and p.name.lower().startswith(model))
    picks = []
    for slug in PIECE_SLUGS:
        # exported names may be <model>_<coll>^<slug>_000_u.ydd, a sanitized
        # variant without '^', or the .ydd.xml form — match loosely on slug
        for marker in (f"^{slug}_000", f"_{slug}_000", f"^{slug}_", f"_{slug}_"):
            cands = [p for p in all_assets if marker in p.name.lower()]
            if cands:
                # prefer binary .ydd over .ydd.xml when both exist
                cands.sort(key=lambda p: (p.name.lower().endswith(".xml"), p.name))
                picks.append(cands[0])
                break
    return picks


def stream_listing(stream: Path, limit: int = 60) -> list[str]:
    if not stream.is_dir():
        return [f"<missing dir: {stream}>"]
    return sorted(p.name for p in stream.rglob("*") if p.is_file())[:limit]


def scene_bbox():
    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            w = obj.matrix_world @ __import__("mathutils").Vector(corner)
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    return lo, hi


def rig_camera(yaw_deg: float):
    from mathutils import Vector
    lo, hi = scene_bbox()
    center = Vector(((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2))
    height = max(hi[2] - lo[2], 0.5)
    # generous distance + wide-ish lens: never end up inside the mesh
    dist = max(height * 2.6, 3.0)
    yaw = math.radians(yaw_deg)
    loc = center + Vector((math.sin(yaw) * dist, -math.cos(yaw) * dist,
                           height * 0.08))
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 40
    cam_data.clip_start = 0.02
    cam_data.clip_end = 500.0
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = loc
    cam.rotation_euler = (center - loc).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam

    key = bpy.data.lights.new("key", type="AREA")
    key.energy = 900
    key.size = 3.0
    ko = bpy.data.objects.new("key", key)
    ko.location = center + Vector((1.6, -1.8, 1.2))
    ko.rotation_euler = (center - ko.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.collection.objects.link(ko)

    sun = bpy.data.lights.new("fill", type="SUN")
    sun.energy = 2.5
    so = bpy.data.objects.new("fill", sun)
    so.rotation_euler = (math.radians(55), 0, math.radians(160))
    bpy.context.collection.objects.link(so)

    world = bpy.data.worlds.new("w")
    world.color = (0.22, 0.22, 0.24)
    bpy.context.scene.world = world


def clear_default_scene() -> None:
    """Remove Blender's startup objects (Cube, Light, Camera) — the 2m default
    cube at the origin otherwise swallows the mannequin and the render."""
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def main() -> None:
    args = parse_args()
    stream = Path(args.stream)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    clear_default_scene()

    pieces = find_pieces(stream, args.gender)
    if not pieces:
        write_result(args.result, {
            "status": "failed",
            "reason": f"no converted body pieces found in {stream}",
            "evidence": {"stream_files": stream_listing(stream)}})
        return

    imported, import_errors = [], []
    for p in pieces:
        try:
            sollumz_import(str(p))
            imported.append(p.name)
        except Exception as e:  # noqa: BLE001
            import_errors.append(f"{p.name}: {e}")
    if not any(o.type == "MESH" for o in bpy.data.objects):
        write_result(args.result, {
            "status": "failed",
            "reason": "no meshes imported",
            "evidence": {"tried": [p.name for p in pieces],
                         "errors": import_errors}})
        return

    scene = bpy.context.scene
    scene.render.resolution_x = 900
    scene.render.resolution_y = 1400
    scene.render.image_settings.file_format = "PNG"

    renders = []
    for label, yaw in (("front", 0), ("three_quarter", 35)):
        # remove previous camera/lights, keep meshes
        for obj in list(bpy.data.objects):
            if obj.type in ("CAMERA", "LIGHT"):
                bpy.data.objects.remove(obj, do_unlink=True)
        rig_camera(yaw)
        png = out_dir / f"{args.gender}_{label}.png"
        scene.render.filepath = str(png)
        try:
            bpy.ops.render.render(write_still=True)
            renders.append(png.name)
        except Exception as e:  # noqa: BLE001
            import_errors.append(f"render {label}: {e}")

    lo, hi = scene_bbox()
    write_result(args.result, {
        "status": "ok" if renders else "failed",
        "renders": renders,
        "imported": imported,
        "errors": import_errors,
        "diagnostics": {
            "bbox_lo": [round(v, 3) for v in lo],
            "bbox_hi": [round(v, 3) for v in hi],
            "objects": [
                {"name": o.name, "type": o.type,
                 "loc": [round(v, 2) for v in o.location],
                 "scale": [round(v, 2) for v in o.scale]}
                for o in bpy.data.objects
            ][:60],
        },
    })


if __name__ == "__main__":
    main()
