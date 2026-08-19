"""Data model for the mannequin pipeline."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Optional

# GTA V freemode ped component slots
COMPONENT_SLUGS = {
    "head": 0, "berd": 1, "hair": 2, "uppr": 3, "lowr": 4, "hand": 5,
    "feet": 6, "teef": 7, "accs": 8, "task": 9, "decl": 10, "jbib": 11,
}
COMPONENT_IDS = {v: k for k, v in COMPONENT_SLUGS.items()}

PROP_SLUGS = {
    "p_head": 0, "p_eyes": 1, "p_ears": 2, "p_mouth": 3,
    "p_lhand": 4, "p_rhand": 5, "p_lwrist": 6, "p_rwrist": 7, "p_hip": 8,
}

# mannequin body replaces these outright (base skin carriers)
BODY_SKIN_COMPONENTS = {0, 2, 3, 5, 7}  # head, hair, uppr, hand, teef
# these garment slots may embed skin and need per-drawable analysis
ANALYZE_COMPONENTS = {1, 4, 6, 8, 11}
# these are effectively always skin-free overlays
SKIN_FREE_COMPONENTS = {9, 10}

# CodeWalker drawable naming:
#   mp_m_freemode_01^uppr_000_u.ydd            (base collection)
#   mp_m_freemode_01_mp_heist3^jbib_004_u.ydd  (DLC collection 'mp_heist3')
DRAWABLE_RE = re.compile(
    r"^(?P<model>mp_[mf]_freemode_01)(?:_(?P<collection>[a-z0-9_]+?))?"
    r"\^(?P<slug>head|berd|hair|uppr|lowr|hand|feet|teef|accs|task|decl|jbib|p_[a-z]+)"
    r"_(?P<idx>\d{3})(?:_(?P<race>[a-z]))?$"
)

# texture naming: mp_m_freemode_01^uppr_diff_000_a_whi  /  ..._b_uni ...
TEXTURE_RE = re.compile(
    r"^(?P<model>mp_[mf]_freemode_01)(?:_(?P<collection>[a-z0-9_]+?))?"
    r"\^(?P<slug>[a-z_]+)_diff_(?P<idx>\d{3})_(?P<tex>[a-z])(?:_(?P<race>[a-z]+))?$"
)


@dataclass
class DrawableRecord:
    gender: str                 # 'male' | 'female'
    model: str
    collection: str             # '' = base game collection
    component_slug: str
    component_id: int
    local_drawable: int
    is_prop: bool
    race_suffix: str
    source_path: str
    texture_count: int = 0
    texture_names: list[str] = field(default_factory=list)

    @property
    def key(self) -> str:
        kind = "prop" if self.is_prop else "comp"
        return f"{self.gender}:{kind}{self.component_id}:{self.collection}:{self.local_drawable}"


@dataclass
class Classification:
    key: str
    category: str          # body_skin | skin_free | convert | incompatible | ambiguous
    reason: str
    skin_pixel_ratio: Optional[float] = None
    resolution: Optional[str] = None   # manual override: skin_free | convert | incompatible

    @property
    def effective(self) -> str:
        return self.resolution or self.category


def parse_drawable_name(stem: str, gender_hint: Optional[str] = None):
    """Parse a CodeWalker-exported drawable stem into identity fields.

    Returns dict or None if the name is not a freemode component/prop drawable.
    """
    m = DRAWABLE_RE.match(stem.lower())
    if not m:
        return None
    model = m.group("model")
    gender = "male" if "_m_" in model else "female"
    if gender_hint and gender_hint != gender:
        return None
    slug = m.group("slug")
    is_prop = slug.startswith("p_")
    if is_prop:
        comp = PROP_SLUGS.get(slug)
    else:
        comp = COMPONENT_SLUGS.get(slug)
    if comp is None:
        return None
    return {
        "gender": gender,
        "model": model,
        "collection": m.group("collection") or "",
        "component_slug": slug,
        "component_id": comp,
        "local_drawable": int(m.group("idx")),
        "is_prop": is_prop,
        "race_suffix": m.group("race") or "",
    }


def load_json(path: Path, default=None):
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def record_to_dict(r) -> dict:
    return asdict(r)
