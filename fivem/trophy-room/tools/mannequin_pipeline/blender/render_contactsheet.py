"""Render validation contact sheets for converted assets.

  blender --background --factory-startup --addons sollumz \
      --python render_contactsheet.py -- --assets <stream_dir> --out captures/blender

Renders each drawable front/side under two light rigs (dark-room warm spot +
neutral daylight) so material response can be reviewed at a glance.

NOTE: these renders are pipeline QA only — they are explicitly NOT FiveM
acceptance evidence (acceptance §5/§21.20).
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from convert_garment import sollumz_import  # noqa: E402


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--assets", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--limit", type=int, default=0)
    return ap.parse_args(argv)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def rig(kind: str):
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (0.0, -2.6, 1.0)
    cam.rotation_euler = (math.radians(85), 0, 0)
    bpy.context.scene.camera = cam

    if kind == "dark":
        light_data = bpy.data.lights.new("spot", type="SPOT")
        light_data.energy = 400
        light_data.color = (1.0, 0.85, 0.6)
        light = bpy.data.objects.new("spot", light_data)
        light.location = (0.6, -1.4, 2.4)
        light.rotation_euler = (math.radians(60), 0, math.radians(15))
        bpy.context.collection.objects.link(light)
        bpy.context.scene.world = bpy.data.worlds.new("w")
        bpy.context.scene.world.color = (0.01, 0.01, 0.015)
    else:
        light_data = bpy.data.lights.new("sun", type="SUN")
        light_data.energy = 4
        light = bpy.data.objects.new("sun", light_data)
        light.rotation_euler = (math.radians(50), 0, math.radians(-30))
        bpy.context.collection.objects.link(light)


def main():
    args = parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    assets = sorted(Path(args.assets).glob("*.ydd*"))
    if args.limit:
        assets = assets[: args.limit]

    scene = bpy.context.scene
    for asset in assets:
        for kind in ("dark", "day"):
            for angle, yaw in (("front", 0), ("side", 90)):
                clear_scene()
                rig(kind)
                try:
                    sollumz_import(str(asset))
                except Exception as e:  # noqa: BLE001
                    print(f"skip {asset.name}: {e}")
                    continue
                for o in bpy.data.objects:
                    if o.type in ("MESH", "ARMATURE") and o.parent is None:
                        o.rotation_euler = (0, 0, math.radians(yaw))
                scene = bpy.context.scene
                scene.render.resolution_x = 640
                scene.render.resolution_y = 960
                scene.render.filepath = str(
                    out / f"{asset.name.split('.')[0]}_{kind}_{angle}.png")
                bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
