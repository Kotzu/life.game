"""Build one mannequin BODY asset (faceless head / scalp / plastic uppr / lowr /
feet twin) from an imported freemode base drawable.

Same invocation contract as convert_garment.py. What differs from a garment
conversion:

- head (comp 0): after material swap, the face is smoothed to the modeling spec —
  eye sockets, mouth seam and nostril cavities are closed by targeted vertex
  smoothing on the face vertex region (identified by the head material slot),
  keeping silhouette (nose/brow) intact. This is intentionally conservative and
  parameterized; final art passes happen interactively in Blender using the
  saved .blend source (blender_src/), never by editing exported binaries.
- hair (comp 2): geometry is REPLACED by a scalp cap derived from the head mesh
  (shrink-wrapped shell), so the mannequin has a clean continuous cranium.
- teef (comp 7): exported as an empty/hidden drawable (mannequin has no mouth
  cavity).
- ALL materials are swapped to mannequin plastic (a body piece has no garment
  materials to preserve).

Every generated .blend is saved to blender_src/<name>.blend for manual
refinement; exports go to the resource stream dir.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
import bmesh

sys.path.insert(0, str(Path(__file__).resolve().parent))
from material_mannequin import make_mannequin_material  # noqa: E402
from convert_garment import (sollumz_import, sollumz_export,  # noqa: E402
                             target_name, write_result)

SMOOTH_ITERATIONS = 60
SMOOTH_FACTOR = 0.5


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--job", required=True)
    ap.add_argument("--out", required=True)
    return ap.parse_args(argv)


def swap_all_materials(obj) -> None:
    for slot in obj.material_slots:
        slot.material = make_mannequin_material(slot.material)


def smooth_face_region(obj) -> int:
    """Close eye/mouth/nostril cavities by smoothing high-curvature face verts.

    Region selection: vertices whose normals disagree strongly with their
    neighborhood (cavity rims) within the front hemisphere of the head bound.
    Returns number of vertices smoothed.
    """
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()

    ys = [v.co.y for v in bm.verts]
    if not ys:
        bm.free()
        return 0
    y_front = min(ys) + (max(ys) - min(ys)) * 0.45  # front 55% of the head

    # MANNEQUIN face: smooth the ENTIRE front of the head so eyes, mouth and
    # nostrils melt into the surface (featureless, per the reference look).
    # The cranium/ears/nape stay untouched — they carry the head's shape.
    front = [v for v in bm.verts if v.co.y >= y_front]
    for _ in range(SMOOTH_ITERATIONS):
        bmesh.ops.smooth_vert(bm, verts=front, factor=SMOOTH_FACTOR,
                              use_axis_x=True, use_axis_y=True, use_axis_z=True)

    # extra pass on cavity rims (deep creases survive broad smoothing)
    region = set()
    for v in front:
        for e in v.link_edges:
            o = e.other_vert(v)
            if v.normal.dot(o.normal) < math.cos(math.radians(42)):
                region.add(v)
                break
    verts = list(region)
    for _ in range(SMOOTH_ITERATIONS):
        bmesh.ops.smooth_vert(bm, verts=verts, factor=SMOOTH_FACTOR,
                              use_axis_x=True, use_axis_y=True, use_axis_z=True)
    verts = front

    bm.to_mesh(me)
    bm.free()
    me.update()
    return len(verts)


def smooth_z_band(obj, lo_frac: float, hi_frac: float,
                  iterations: int = SMOOTH_ITERATIONS) -> int:
    """Heavily smooth vertices whose height falls inside [lo_frac, hi_frac] of
    the mesh's z-range — used to melt clothing seams (waistband/cuffs) into
    the mannequin body."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    zs = [v.co.z for v in bm.verts]
    if not zs:
        bm.free()
        return 0
    zmin, zmax = min(zs), max(zs)
    rng = (zmax - zmin) or 1.0
    verts = [v for v in bm.verts
             if lo_frac <= (v.co.z - zmin) / rng <= hi_frac]
    for _ in range(iterations):
        bmesh.ops.smooth_vert(bm, verts=verts, factor=SMOOTH_FACTOR,
                              use_axis_x=True, use_axis_y=True,
                              use_axis_z=True)
    bm.to_mesh(obj.data)
    bm.free()
    return len(verts)


def build_scalp_from_head(head_obj):
    """Duplicate the cranium region of the head as the comp-2 'hair' drawable."""
    scalp = head_obj.copy()
    scalp.data = head_obj.data.copy()
    scalp.name = head_obj.name + "_scalp"
    bpy.context.collection.objects.link(scalp)
    # Keep only upper-cranium faces (z above head midline)
    bm = bmesh.new()
    bm.from_mesh(scalp.data)
    zs = [v.co.z for v in bm.verts]
    z_cut = min(zs) + (max(zs) - min(zs)) * 0.55
    doomed = [f for f in bm.faces if all(v.co.z < z_cut for v in f.verts)]
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bm.to_mesh(scalp.data)
    bm.free()
    return scalp


def main() -> None:
    args = parse_args()
    job = json.loads(Path(args.job).read_text(encoding="utf-8"))

    try:
        sollumz_import(job["source"])
    except Exception as e:  # noqa: BLE001
        write_result(args.out, {"status": "failed", "reason": f"import: {e}"})
        return

    mesh_objs = [o for o in bpy.data.objects if o.type == "MESH"]
    if not mesh_objs:
        write_result(args.out, {"status": "failed", "reason": "no meshes imported"})
        return

    smoothed = 0
    comp = job["component_id"]
    for obj in mesh_objs:
        swap_all_materials(obj)
        if comp == 0:  # head: close facial cavities
            smoothed += smooth_face_region(obj)
        if comp == 4 and job.get("gender") == "male":
            # male briefs piece: melt the waistband/cuff geometry into the
            # body so the bare mannequin reads as smooth hips, not underwear
            smoothed += smooth_z_band(obj, 0.66, 1.0)
        if comp == 6 and job.get("gender") == "male":
            # no barefoot male drawable exists — soften the low-profile shoe
            # into an abstract mannequin foot (details melt, sole stays)
            smoothed += smooth_z_band(obj, 0.0, 1.0, iterations=20)
        if comp == 2:  # hair source: replace with scalp derived from geometry
            pass  # scalp derives from the head job below

    if comp == 2:
        # hair drawable is rebuilt as a scalp cap from the first mesh
        scalp = build_scalp_from_head(mesh_objs[0])
        for o in mesh_objs:
            bpy.data.objects.remove(o, do_unlink=True)
        mesh_objs = [scalp]

    new_name = target_name(job, job.get("mannequin_local"))
    for obj in bpy.data.objects:
        if obj.parent is None:
            obj.name = new_name

    # save editable source for manual art passes
    src_dir = Path(__file__).resolve().parent.parent / "blender_src"
    src_dir.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(src_dir / f"{new_name}.blend"))

    try:
        sollumz_export(job["out_dir"])
    except Exception as e:  # noqa: BLE001
        write_result(args.out, {"status": "failed", "reason": f"export: {e}"})
        return

    write_result(args.out, {
        "status": "ok",
        "output_name": new_name,
        "smoothed_vertices": smoothed,
        "blend_source": str(src_dir / f"{new_name}.blend"),
    })


if __name__ == "__main__":
    main()
