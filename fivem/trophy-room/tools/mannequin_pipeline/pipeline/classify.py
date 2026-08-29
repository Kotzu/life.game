"""classify — decide, per drawable, whether it is body skin, skin-free,
needs conversion, or must go to manual review. The pipeline never guesses:
anything inside the ambiguity band (or unanalyzable without Pillow) is queued
for a human decision.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Optional

from .model import (ANALYZE_COMPONENTS, BODY_SKIN_COMPONENTS,
                    SKIN_FREE_COMPONENTS, Classification, load_json, save_json)

try:  # optional — enables automatic texture analysis
    from PIL import Image  # type: ignore
    HAVE_PIL = True
except Exception:  # pragma: no cover - environment dependent
    Image = None
    HAVE_PIL = False

# Inclusive skin-tone chroma boxes in (Cb, Cr) after RGB->YCbCr, covering pale
# through dark tones. Deliberately wide: false positives only cause manual
# review, never a wrong automatic 'skin_free'.
SKIN_CB = (77, 135)
SKIN_CR = (133, 180)


def skin_pixel_ratio(png_path: Path) -> Optional[float]:
    """Fraction of non-transparent pixels that fall in the skin chroma box."""
    if not HAVE_PIL or not png_path.exists():
        return None
    try:
        img = Image.open(png_path).convert("RGBA")
    except Exception:  # unreadable/exotic compression -> treat as not analyzable
        return None
    small = img.resize((min(img.width, 256), min(img.height, 256)))
    ycc = small.convert("RGB").convert("YCbCr")
    alpha = small.getchannel("A")
    total = 0
    hits = 0
    ycc_px = ycc.load()
    a_px = alpha.load()
    for y in range(small.height):
        for x in range(small.width):
            if a_px[x, y] < 32:
                continue
            total += 1
            _, cb, cr = ycc_px[x, y]
            if SKIN_CB[0] <= cb <= SKIN_CB[1] and SKIN_CR[0] <= cr <= SKIN_CR[1]:
                hits += 1
    if total == 0:
        return 0.0
    return hits / total


def classify_record(rec: dict, cfg: dict, png_dir: Path,
                    prior: Optional[dict] = None) -> Classification:
    key = _key(rec)
    comp = rec["component_id"]
    is_prop = rec["is_prop"]

    if prior and prior.get("resolution"):
        c = Classification(key=key, category=prior["category"],
                           reason=prior["reason"],
                           skin_pixel_ratio=prior.get("skin_pixel_ratio"))
        c.resolution = prior["resolution"]
        return c

    if is_prop:
        return Classification(key, "skin_free",
                              "props carry no body skin (manifest exception list may override)")
    if comp in BODY_SKIN_COMPONENTS:
        return Classification(key, "body_skin",
                              "base skin carrier — replaced by mannequin body set")
    if comp in SKIN_FREE_COMPONENTS:
        return Classification(key, "skin_free", "overlay/decal slot never carries skin")
    # designated base-body drawables (lowr/feet/jbib...): converted into FULL
    # plastic pieces forming the bare mannequin figure. Freemode has no torso
    # under clothing (the chest always comes from the worn top), so the
    # mannequin's torso is a designated fitted top turned entirely to plastic.
    # Values are an index, or {"male": i, "female": j} for per-gender picks.
    body_base = cfg.get("body_base", {"4": 0, "6": 0})
    designated = body_base.get(str(comp))
    if isinstance(designated, dict):
        designated = designated.get(rec["gender"])
    if (designated is not None and rec["collection"] == ""
            and rec["local_drawable"] == int(designated)):
        return Classification(key, "body_skin",
                              "designated base-body drawable — mannequin base piece")
    if comp in ANALYZE_COMPONENTS:
        return _classify_by_texture(key, rec, cfg, png_dir)
    return Classification(key, "ambiguous", f"unknown component {comp}")


# Rockstar's freemode convention, verified 114/114 against Blender material
# evidence from the full base-game conversion run: a garment embeds skin iff
# its diffuse textures carry a race suffix (_whi/_bla/...); '_uni' (universal)
# textures never contain skin — visible skin comes from the body components
# underneath, which the mannequin body set already replaces.
RACE_SUFFIX_RE = re.compile(
    r"_(whi|bla|chi|lat|ara|bal|jap|kor|mid|pak|sou|vie)$")


def _classify_by_texture(key: str, rec: dict, cfg: dict, png_dir: Path) -> Classification:
    texs = rec.get("texture_names", [])
    if not texs:
        return Classification(
            key, "ambiguous",
            "no textures found for garment — cannot determine skin embedding; "
            "manual review required")
    race = sorted({RACE_SUFFIX_RE.search(t).group(1)
                   for t in texs if RACE_SUFFIX_RE.search(t)})
    ratio = _worst_skin_ratio(rec, cfg, png_dir)
    if race:
        return Classification(
            key, "convert",
            f"race-suffixed diffuse textures ({', '.join(race)}) embed "
            "per-race skin", ratio)
    # nude/underwear pieces (bare chest, bra, boxers...) use _uni textures that
    # are themselves skin images — the pixel evidence catches what names can't
    thr = cfg.get("skin_ratio_convert", 0.35)
    if ratio is not None and ratio >= thr:
        return Classification(
            key, "convert",
            f"skin-dominant texture (worst ratio {ratio:.2f} >= {thr}) — "
            "nude/underwear piece, converted fully to mannequin material",
            ratio)
    return Classification(
        key, "skin_free",
        "universal (_uni) textures with low skin-pixel evidence — garment "
        "carries no embedded skin", ratio)


def _worst_skin_ratio(rec: dict, cfg: dict, png_dir: Path):
    """Highest skin-pixel ratio across the garment's texture dumps, or None.
    Recorded as evidence only — the race-suffix rule decides the category."""
    ratios = []
    missing = []
    # plain in-ytd names repeat across collections, so a per-source-folder
    # subdir (e.g. _png/mp_m_freemode_01_mp_heist3/) disambiguates them
    subdir = rec["model"] + (f"_{rec['collection']}" if rec.get("collection") else "")
    # CodeWalker's Export XML also drops the textures as .dds next to the
    # exported .ytd.xml (either <stem>.dds or a <stem>/ folder of .dds), so a
    # separate PNG dump is not required — look there too.
    srcdir = Path(rec["source_path"]).parent if rec.get("source_path") else None
    for tex in rec.get("texture_names", []):
        # PNG dumps may be named by the full streaming name or by the plain
        # in-ytd texture name (CodeWalker "Save All" uses the latter) — try
        # the canonical name, then the per-folder plain name, then flat plain.
        plain = tex.split("^", 1)[-1]
        r = None
        for cand in dict.fromkeys((tex, f"{subdir}/{plain}", plain)):
            r = skin_pixel_ratio(png_dir / f"{cand}.png")
            if r is not None:
                break
        if r is None and srcdir is not None:
            r = skin_pixel_ratio(srcdir / f"{plain}.dds")
        if r is None and srcdir is not None and (srcdir / plain).is_dir():
            # worst (highest) ratio across the dictionary's textures — the
            # conservative choice: any skin-looking layer flags the garment
            sub = [skin_pixel_ratio(p) for p in sorted((srcdir / plain).glob("*.dds"))]
            sub = [x for x in sub if x is not None]
            if sub:
                r = max(sub)
        if r is None:
            missing.append(tex)
        else:
            ratios.append(r)
    return max(ratios) if ratios else None


def _key(rec: dict) -> str:
    kind = "prop" if rec["is_prop"] else "comp"
    return f"{rec['gender']}:{kind}{rec['component_id']}:{rec['collection']}:{rec['local_drawable']}"


def classify(build_dir: Path, cfg: dict) -> dict:
    catalog = load_json(build_dir / "scan_catalog.json")
    if not catalog:
        raise SystemExit("run `scan` first — build/scan_catalog.json missing")
    png_dir = Path(cfg.get("texture_png_dir", "extracted/_png"))

    prior_cls = load_json(build_dir / "classification.json", {}) or {}
    prior_items = prior_cls.get("items", {})
    # merge resolved entries from the manual review queue
    queue_path = Path("manual_review_queue.json")
    queue = load_json(queue_path, {"items": []}) or {"items": []}
    resolutions = {i["key"]: i["resolution"] for i in queue.get("items", [])
                   if i.get("resolution")}

    items = {}
    review = []
    for k, rec in catalog["drawables"].items():
        prior = prior_items.get(k)
        if prior is None and k in resolutions:
            prior = {"category": "ambiguous", "reason": "manual resolution",
                     "resolution": resolutions[k]}
        elif prior is not None and k in resolutions:
            prior = dict(prior, resolution=resolutions[k])
        c = classify_record(rec, cfg, png_dir, prior)
        items[k] = {
            "category": c.category,
            "effective": c.effective,
            "reason": c.reason,
            "skin_pixel_ratio": c.skin_pixel_ratio,
            "resolution": c.resolution,
        }
        if c.effective == "ambiguous":
            review.append({
                "key": k,
                "reason": c.reason,
                "evidence": {
                    "skin_pixel_ratio": c.skin_pixel_ratio,
                    "textures": rec.get("texture_names", []),
                    "source": rec.get("source_path"),
                },
                "resolution": None,
            })

    out = {
        "schema": "kotzu_classification/1",
        "counts": _counts(items),
        "items": items,
    }
    save_json(build_dir / "classification.json", out)

    # keep unresolved + already-resolved entries in the queue file
    resolved = [i for i in queue.get("items", []) if i.get("resolution")]
    save_json(queue_path, {
        "schema": "kotzu_manual_review/1",
        "unresolved": len(review),
        "items": resolved + review,
    })
    return out


def _counts(items: dict) -> dict:
    counts: dict[str, int] = {}
    for v in items.values():
        counts[v["effective"]] = counts.get(v["effective"], 0) + 1
    return counts
