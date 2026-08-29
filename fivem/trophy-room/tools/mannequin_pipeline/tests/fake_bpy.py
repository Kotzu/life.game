"""Minimal `bpy` + Sollumz stand-ins so the Blender job LOGIC can run headlessly.

This is NOT Blender: it emulates just enough of the data model (objects,
materials, image texture nodes, material slots) for the decision logic in
convert_garment.py / material_mannequin.py to execute — material classification,
the ambiguous/failed branches, output naming, result-JSON writing. It cannot
validate geometry, weights or actual export; those still require real Blender
(that gap is documented in the pipeline README).
"""

from __future__ import annotations

import sys
import types


# ------------------------------------------------------------------ data model
class Image:
    def __init__(self, name, width=0, height=0, alpha=False):
        self.name = name
        self.width = width
        self.height = height
        self.pixels = _PixelList()
        self.packed = False

    def pack(self):
        self.packed = True


class _PixelList(list):
    def __setitem__(self, key, value):
        # accept `img.pixels[:] = [...]` without allocating a huge buffer
        if isinstance(key, slice):
            return
        super().__setitem__(key, value)


class _TexNode:
    type = "TEX_IMAGE"

    def __init__(self, name="Image Texture", image=None):
        self.name = name
        self.image = image
        self.outputs = [types.SimpleNamespace(default_value=0.0)]


class _NodeTree:
    def __init__(self):
        self.nodes = _NodeCollection()
        self.links = types.SimpleNamespace(new=lambda a, b: None)


class _NodeCollection(list):
    def get(self, name):
        for n in self:
            if getattr(n, "name", None) == name:
                return n
        return None


class Material:
    def __init__(self, name):
        self.name = name
        self.use_nodes = True
        self.node_tree = _NodeTree()
        self.sollum_shader = None
        # Sollumz-registered custom props the real addon adds:
        self.sollum_type = None
        self.shader_properties = types.SimpleNamespace(name="", filename="")

    def copy(self):
        # Blender's Material.copy() auto-links the new datablock into
        # bpy.data.materials — mirror that so name-based caches behave the same.
        m = Material(self.name + ".001")
        m.use_nodes = self.use_nodes
        for n in self.node_tree.nodes:
            if isinstance(n, _TexNode):
                m.node_tree.nodes.append(_TexNode(n.name, n.image))
        bpy = sys.modules.get("bpy")
        if bpy is not None:
            bpy.data.materials.append(m)
        return m


class _Slot:
    def __init__(self, material=None):
        self.material = material


class Object:
    def __init__(self, name, obj_type="MESH", materials=None):
        self.name = name
        self.type = obj_type
        self.parent = None
        self.material_slots = [_Slot(m) for m in (materials or [])]
        self.data = types.SimpleNamespace(name=name + "_data")
        self.rotation_euler = [0.0, 0.0, 0.0]
        self.location = [0.0, 0.0, 0.0]
        self.selected = False

    def select_set(self, value):
        self.selected = bool(value)


# ------------------------------------------------------------------ collections
class _DataColl(list):
    def __init__(self, factory):
        super().__init__()
        self._factory = factory

    def new(self, *args, **kwargs):
        obj = self._factory(*args, **kwargs)
        self.append(obj)
        return obj

    def get(self, name):
        for x in self:
            if getattr(x, "name", None) == name:
                return x
        return None

    def remove(self, obj, do_unlink=True):
        if obj in self:
            super().remove(obj)


class _Data:
    def __init__(self):
        self.images = _DataColl(Image)
        self.materials = _DataColl(Material)
        self.objects = _DataColl(Object)
        self.cameras = _DataColl(lambda name: types.SimpleNamespace(name=name))
        self.lights = _DataColl(lambda name, type=None: types.SimpleNamespace(name=name, type=type))
        self.worlds = _DataColl(lambda name: types.SimpleNamespace(name=name, color=(0, 0, 0)))


# ------------------------------------------------------------------ ops (Sollumz)
class _OpsResult(dict):
    pass


class SollumzOps:
    """Records import/export calls; the test decides success/failure."""

    def __init__(self, controller):
        self._c = controller

    def import_assets(self, **kw):
        return self._c.do_import(kw)

    def export_assets(self, **kw):
        return self._c.do_export(kw)

    # legacy op ids that should NOT exist in Sollumz 2.9 (must raise)
    def importydd(self, **kw):
        raise RuntimeError("no importydd operator")

    def exportydd(self, **kw):
        raise RuntimeError("no exportydd operator")


class _ImportSceneOps:
    def ydd(self, **kw):
        raise RuntimeError("no import_scene.ydd operator")


def install(controller):
    """Build the fake bpy module and install it into sys.modules."""
    bpy = types.ModuleType("bpy")
    bpy.data = _Data()
    bpy.app = types.SimpleNamespace(version=(4, 2, 0), version_string="4.2.0 (fake)")

    coll = types.SimpleNamespace(objects=_LinkColl(bpy.data.objects))
    bpy.context = types.SimpleNamespace(
        collection=coll,
        view_layer=types.SimpleNamespace(objects=types.SimpleNamespace(active=None)),
        scene=types.SimpleNamespace(
            world=None,
            camera=None,
            render=types.SimpleNamespace(resolution_x=0, resolution_y=0, filepath=""),
        ),
    )

    bpy.ops = types.SimpleNamespace(
        sollumz=SollumzOps(controller),
        import_scene=_ImportSceneOps(),
        render=types.SimpleNamespace(render=lambda **kw: None),
        wm=types.SimpleNamespace(
            read_factory_settings=lambda **kw: None,
            save_as_mainfile=lambda **kw: controller.saved.append(kw.get("filepath")),
        ),
    )

    bpy.types = types.SimpleNamespace(Image=Image, Material=Material, NodeTree=_NodeTree)
    bpy.props = types.SimpleNamespace()

    sys.modules["bpy"] = bpy

    # a bmesh stub (only build_mannequin_body uses it; not exercised here)
    bmesh = types.ModuleType("bmesh")
    bmesh.new = lambda: types.SimpleNamespace(
        verts=[], faces=[], from_mesh=lambda m: None, to_mesh=lambda m: None, free=lambda: None)
    bmesh.ops = types.SimpleNamespace(smooth_vert=lambda *a, **k: None,
                                      delete=lambda *a, **k: None)
    sys.modules["bmesh"] = bmesh

    return bpy


class _LinkColl:
    def __init__(self, backing):
        self._backing = backing

    def link(self, obj):
        if obj not in self._backing:
            self._backing.append(obj)


class Controller:
    """Test-controlled Sollumz behaviour + recorded side effects."""

    def __init__(self, import_objects=None, import_fails=False, export_fails=False,
                 export_writes_nothing=False):
        self.import_objects = import_objects or []
        self.import_fails = import_fails
        self.export_fails = export_fails
        # like real Sollumz in --background with nothing selected: the operator
        # returns FINISHED without writing any file
        self.export_writes_nothing = export_writes_nothing
        self.exported = []
        self.saved = []

    def do_import(self, kw):
        if self.import_fails:
            raise RuntimeError("simulated import failure")
        import bpy
        for obj in self.import_objects:
            bpy.data.objects.append(obj)
            bpy.context.collection.objects.link(obj)
        return {"FINISHED"}

    def do_export(self, kw):
        if self.export_fails:
            raise RuntimeError("simulated export failure")
        self.exported.append(kw)
        if not self.export_writes_nothing:
            d = kw.get("directory")
            if d:
                from pathlib import Path
                Path(d).mkdir(parents=True, exist_ok=True)
                (Path(d) / "exported.ydd").write_bytes(b"fake")
        return {"FINISHED"}
