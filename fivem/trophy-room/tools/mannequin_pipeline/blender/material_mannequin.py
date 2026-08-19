"""Shared helpers for mannequin conversion inside Blender + Sollumz.

Runs INSIDE Blender. Not importable outside it.
"""

from __future__ import annotations

import bpy

# Off-white, matte/semi-matte plastic. Kept as constants so the male/female
# body and every converted garment share the identical material response.
MANNEQUIN_DIFFUSE = (0.906, 0.894, 0.871, 1.0)  # warm off-white
MANNEQUIN_SPEC_INTENSITY = 0.18
MANNEQUIN_SPEC_FALLOFF = 220.0                  # tight-ish highlight, semi-matte
MANNEQUIN_TEXTURE_NAME = "kotzu_mannequin_plastic"
MANNEQUIN_TEXTURE_SIZE = 64                     # flat color; tiny texture budget

# Heuristics for identifying human-skin materials on ped drawables.
SKIN_TEXTURE_TOKENS = (
    "head_diff", "uppr_diff_000", "lowr_diff_000", "skin", "_whi", "_bla",
    "feet_diff_000", "hand",
)
SKIN_SHADER_TOKENS = ("ped.sps", "ped_default", "ped_wrinkle", "ped_hair")


def ensure_plastic_image() -> bpy.types.Image:
    img = bpy.data.images.get(MANNEQUIN_TEXTURE_NAME)
    if img is None:
        s = MANNEQUIN_TEXTURE_SIZE
        img = bpy.data.images.new(MANNEQUIN_TEXTURE_NAME, s, s, alpha=False)
        px = list(MANNEQUIN_DIFFUSE) * (s * s)
        img.pixels[:] = px
        img.pack()
    return img


def material_diffuse_names(mat) -> list[str]:
    names = []
    if mat and mat.use_nodes:
        for node in mat.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image:
                names.append(node.image.name.lower())
    return names


def looks_like_skin(mat, hints: dict | None = None) -> tuple[bool, str]:
    """Return (is_skin, why). Conservative: unknown -> not skin (caller decides
    whether unknowns make the item ambiguous)."""
    if mat is None:
        return False, "no material"
    name = (mat.name or "").lower()
    shader = getattr(mat, "sollum_shader", None)
    shader_name = ""
    if shader is not None:
        shader_name = str(getattr(shader, "name", shader)).lower()
    hay = " ".join([name, shader_name] + material_diffuse_names(mat))
    for tok in SKIN_TEXTURE_TOKENS:
        if tok in hay:
            return True, f"token '{tok}' in material/texture names"
    if hints:
        for tok in hints.get("extra_skin_tokens", []):
            if tok in hay:
                return True, f"job hint token '{tok}'"
    return False, "no skin tokens"


def make_mannequin_material(source_mat=None) -> bpy.types.Material:
    """Create (once) the mannequin plastic as a Sollumz ped shader material so it
    exports as a game-compatible shader, not a Blender-only BSDF."""
    existing = bpy.data.materials.get("kotzu_mannequin_plastic_mat")
    if existing:
        return existing

    mat = None
    # Preferred: Sollumz shader material creation (API name varies by version)
    try:
        from sollumz.ydr.shader_materials import create_shader  # Sollumz 2.x
        mat = create_shader("ped_default.sps")
    except Exception:
        try:
            from sollumz.shared.shader_materials import create_shader  # newer layouts
            mat = create_shader("ped_default.sps")
        except Exception:
            mat = None

    if mat is None:
        # Fallback: clone the source material so shader params stay valid, then
        # swap its diffuse image. Guarantees export compatibility.
        if source_mat is None:
            raise RuntimeError(
                "Sollumz create_shader API not found and no source material to clone; "
                "update blender/material_mannequin.py for your Sollumz version")
        mat = source_mat.copy()

    mat.name = "kotzu_mannequin_plastic_mat"
    img = ensure_plastic_image()
    if mat.use_nodes:
        for node in mat.node_tree.nodes:
            if node.type == "TEX_IMAGE":
                node.image = img
    # Sollumz exposes shader params as custom value nodes/properties; set the
    # common ones when present.
    for pname, val in (("specularIntensityMult", MANNEQUIN_SPEC_INTENSITY),
                       ("specularFalloffMult", MANNEQUIN_SPEC_FALLOFF)):
        try:
            node = mat.node_tree.nodes.get(pname)
            if node is not None and hasattr(node, "outputs"):
                node.outputs[0].default_value = val
        except Exception:
            pass
    return mat


def replace_skin_materials(obj, hints: dict | None = None) -> dict:
    """Swap skin materials on a mesh object for mannequin plastic.

    Returns {'replaced': [...], 'kept': [...], 'unknown': [...]}
    """
    out = {"replaced": [], "kept": [], "unknown": []}
    if obj.type != "MESH":
        return out
    for slot in obj.material_slots:
        mat = slot.material
        is_skin, why = looks_like_skin(mat, hints)
        label = f"{mat.name if mat else '<none>'} ({why})"
        if is_skin:
            slot.material = make_mannequin_material(mat)
            out["replaced"].append(label)
        elif mat is None:
            out["unknown"].append(label)
        else:
            out["kept"].append(label)
    return out
