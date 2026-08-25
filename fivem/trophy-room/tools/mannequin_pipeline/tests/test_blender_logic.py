"""Execute the REAL Blender job logic against the fake bpy/Sollumz stand-in.

The Blender scripts (blender/material_mannequin.py, blender/convert_garment.py)
are the one code path that never runs in CI because it needs Blender. This
harness installs a minimal fake `bpy` (see tests/fake_bpy.py) into sys.modules,
then imports and runs the actual functions so their DECISION logic — skin vs
garment classification, the ambiguous/failed/ok result branches, output naming
and result-JSON writing — is exercised for real. It cannot validate geometry,
weights or a real .ydd export; that gap still needs Blender and is documented
in the pipeline README.
"""

import importlib
import json
import sys
from pathlib import Path

import pytest

import fake_bpy
from fake_bpy import Controller, Image, Material, Object, _Slot, _TexNode

BLENDER_DIR = str(Path(__file__).resolve().parents[1] / "blender")
if BLENDER_DIR not in sys.path:
    sys.path.insert(0, BLENDER_DIR)


def load_blender(controller):
    """Install the fake bpy for `controller`, then (re)load the real modules so
    their module-level `import bpy` binds to this fresh fake."""
    fake_bpy.install(controller)
    import material_mannequin
    import convert_garment
    importlib.reload(material_mannequin)
    importlib.reload(convert_garment)
    return material_mannequin, convert_garment


def mk_material(name, tex_names=()):
    """A Material whose name + image-texture nodes drive looks_like_skin."""
    m = Material(name)
    for t in tex_names:
        img = Image(t)
        m.node_tree.nodes.append(_TexNode(image=img))
    return m


def mesh(name, materials):
    o = Object(name, "MESH")
    o.material_slots = [_Slot(m) for m in materials]
    return o


# --------------------------------------------------------------- looks_like_skin
def test_looks_like_skin_matches_skin_token():
    mm, _ = load_blender(Controller())
    is_skin, why = mm.looks_like_skin(mk_material("head_diff_000"))
    assert is_skin, why


def test_looks_like_skin_matches_texture_name():
    mm, _ = load_blender(Controller())
    is_skin, _why = mm.looks_like_skin(mk_material("mat0", tex_names=["uppr_diff_000"]))
    assert is_skin


def test_looks_like_skin_garment_is_not_skin():
    mm, _ = load_blender(Controller())
    is_skin, why = mm.looks_like_skin(mk_material("jbib_cloth", tex_names=["jbib_diff_001"]))
    assert not is_skin, why


def test_looks_like_skin_none_material():
    mm, _ = load_blender(Controller())
    is_skin, why = mm.looks_like_skin(None)
    assert not is_skin and why == "no material"


def test_looks_like_skin_job_hint_token():
    mm, _ = load_blender(Controller())
    mat = mk_material("weird_body_part")
    assert not mm.looks_like_skin(mat)[0]
    is_skin, why = mm.looks_like_skin(mat, hints={"extra_skin_tokens": ["weird_body"]})
    assert is_skin and "hint" in why


# ----------------------------------------------------------- replace_skin_materials
def test_replace_skin_materials_branches():
    mm, _ = load_blender(Controller())
    obj = mesh("garment", [
        mk_material("head_diff_000"),      # skin -> replaced
        mk_material("jbib_cloth"),         # garment -> kept
        None,                              # missing -> unknown
    ])
    out = mm.replace_skin_materials(obj)
    assert len(out["replaced"]) == 1
    assert len(out["kept"]) == 1
    assert len(out["unknown"]) == 1
    # the skin slot was actually swapped to the shared plastic material
    assert obj.material_slots[0].material.name == "kotzu_mannequin_plastic_mat"
    # garment slot untouched
    assert obj.material_slots[1].material.name == "jbib_cloth"


def test_replace_skin_materials_shares_one_plastic_material():
    mm, _ = load_blender(Controller())
    a = mesh("a", [mk_material("head_diff_000")])
    b = mesh("b", [mk_material("feet_diff_000")])
    mm.replace_skin_materials(a)
    mm.replace_skin_materials(b)
    # both meshes must reference the SAME plastic material instance (cached)
    assert a.material_slots[0].material is b.material_slots[0].material


def test_replace_skin_materials_ignores_non_mesh():
    mm, _ = load_blender(Controller())
    arm = Object("armature", "ARMATURE")
    out = mm.replace_skin_materials(arm)
    assert out == {"replaced": [], "kept": [], "unknown": []}


# -------------------------------------------------------------------- target_name
def test_target_name_male_and_female():
    _, cg = load_blender(Controller())
    job = {"gender": "male", "collection_name": "kotzu_manqn",
           "component_slug": "jbib", "local_drawable": 4, "kind": "garment"}
    assert cg.target_name(job) == "mp_m_freemode_01_kotzu_manqn^jbib_004_u"
    job["gender"] = "female"
    assert cg.target_name(job).startswith("mp_f_freemode_01_")


def test_target_name_local_override():
    _, cg = load_blender(Controller())
    job = {"gender": "male", "collection_name": "c", "component_slug": "uppr",
           "local_drawable": 4, "kind": "garment"}
    assert cg.target_name(job, mannequin_local=17).endswith("^uppr_017_u")


# --------------------------------------------------------------------- main() e2e
def write_job(tmp_path, **over):
    job = {
        "source": str(tmp_path / "in.ydd"),
        "out_dir": str(tmp_path / "out"),
        "gender": "male",
        "collection_name": "kotzu_manqn",
        "component_slug": "jbib",
        "local_drawable": 3,
        "kind": "garment",
        "hints": {},
    }
    job.update(over)
    p = tmp_path / "job.json"
    p.write_text(json.dumps(job), encoding="utf-8")
    return p


def run_main(cg, tmp_path, job_path):
    out = tmp_path / "result.json"
    sys.argv = ["convert_garment.py", "--", "--job", str(job_path), "--out", str(out)]
    cg.main()
    return json.loads(out.read_text(encoding="utf-8"))


def test_main_import_failure_is_failed(tmp_path):
    _, cg = load_blender(Controller(import_fails=True))
    res = run_main(cg, tmp_path, write_job(tmp_path))
    assert res["status"] == "failed" and res["reason"].startswith("import:")


def test_main_no_meshes_is_failed(tmp_path):
    # import succeeds but yields no mesh objects
    _, cg = load_blender(Controller(import_objects=[]))
    res = run_main(cg, tmp_path, write_job(tmp_path))
    assert res["status"] == "failed" and "no meshes" in res["reason"]


def test_main_unknown_material_is_ambiguous(tmp_path):
    obj = mesh("g", [mk_material("head_diff_000"), None])  # a None slot -> unknown
    _, cg = load_blender(Controller(import_objects=[obj]))
    res = run_main(cg, tmp_path, write_job(tmp_path))
    assert res["status"] == "ambiguous"
    assert res["evidence"]["unknown"]


def test_main_garment_without_skin_is_ambiguous(tmp_path):
    obj = mesh("g", [mk_material("jbib_cloth")])  # only garment, kind=garment
    _, cg = load_blender(Controller(import_objects=[obj]))
    res = run_main(cg, tmp_path, write_job(tmp_path, kind="garment"))
    assert res["status"] == "ambiguous"
    assert "no skin material matched" in res["reason"]


def test_main_success_writes_ok_and_exports(tmp_path):
    obj = mesh("g", [mk_material("head_diff_000"), mk_material("jbib_cloth")])
    ctrl = Controller(import_objects=[obj])
    _, cg = load_blender(ctrl)
    res = run_main(cg, tmp_path, write_job(tmp_path, local_drawable=5))
    assert res["status"] == "ok"
    assert res["output_name"] == "mp_m_freemode_01_kotzu_manqn^jbib_005_u"
    assert res["replaced"] and res["kept"]
    # export actually happened, into the job's out_dir
    assert len(ctrl.exported) == 1
    assert ctrl.exported[0]["directory"] == str(tmp_path / "out")
    # the root object was renamed to the target name
    assert obj.name == res["output_name"]


def test_main_export_failure_is_failed(tmp_path):
    obj = mesh("g", [mk_material("head_diff_000")])
    _, cg = load_blender(Controller(import_objects=[obj], export_fails=True))
    res = run_main(cg, tmp_path, write_job(tmp_path))
    assert res["status"] == "failed" and res["reason"].startswith("export:")


def test_make_material_uses_sollumz_create_shader(tmp_path):
    """Primary path: when Sollumz's create_shader is importable it must be used
    (no source_mat needed), producing the shared plastic material."""
    import types

    calls = []

    def create_shader(filename, in_place_material=None):
        calls.append(filename)
        return Material("ped_default_from_sollumz")

    mod = types.ModuleType("Sollumz.ydr.shader_materials")
    mod.create_shader = create_shader
    pkg = types.ModuleType("Sollumz")
    pkg_ydr = types.ModuleType("Sollumz.ydr")
    sys.modules["Sollumz"] = pkg
    sys.modules["Sollumz.ydr"] = pkg_ydr
    sys.modules["Sollumz.ydr.shader_materials"] = mod
    try:
        mm, _ = load_blender(Controller())
        # no source_mat passed: only the create_shader path can satisfy this
        mat = mm.make_mannequin_material(None)
        assert calls == ["ped_default.sps"]
        assert mat.name == "kotzu_mannequin_plastic_mat"
    finally:
        for k in ("Sollumz.ydr.shader_materials", "Sollumz.ydr", "Sollumz"):
            sys.modules.pop(k, None)


def test_main_non_garment_without_skin_is_ok(tmp_path):
    # kind != garment: the "no skin matched" ambiguity guard must NOT trigger
    obj = mesh("g", [mk_material("jbib_cloth")])
    ctrl = Controller(import_objects=[obj])
    _, cg = load_blender(ctrl)
    res = run_main(cg, tmp_path, write_job(tmp_path, kind="prop"))
    assert res["status"] == "ok"
    assert res["replaced"] == [] and res["kept"]
    assert len(ctrl.exported) == 1
