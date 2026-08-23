"""classify — decide, per drawable, whether it is body skin, skin-free,
needs conversion, or must go to manual review. The pipeline never guesses:
anything inside the ambiguity band (or unanalyzable without Pillow) is queued
for a human decision.
"""

from __future__ import annotations

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
    img = Image.open(png_path).convert("RGBA")
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
    # designated bare-body drawables for lowr/feet: converted into plastic body
    # twins so a bare mannequin has mannequin legs/feet, never engine defaults
    body_base = cfg.get("body_base", {"4": 0, "6": 0})
    if (str(comp) in body_base and rec["collection"] == ""
            and rec["local_drawable"] == int(body_base[str(comp)])):
        return Classification(key, "body_skin",
                              "designated bare-body drawable — mannequin base piece")
    if comp in ANALYZE_COMPONENTS:
        return _classify_by_texture(key, rec, cfg, png_dir)
    return Classification(key, "ambiguous", f"unknown component {comp}")


def _classify_by_texture(key: str, rec: dict, cfg: dict, png_dir: Path) -> Classification:
    lo, hi = cfg.get("ambiguous_band", [0.015, 0.12])
    ratios = []
    missing = []
    for tex in rec.get("texture_names", []):
        png = png_dir / f"{tex}.png"
        r = skin_pixel_ratio(png)
        if r is None:
            missing.append(tex)
        else:
            ratios.append(r)

    if not ratios:
        why = ("Pillow not installed" if not HAVE_PIL
               else f"no PNG dumps found for {len(missing)} texture(s)")
        return Classification(key, "ambiguous",
                              f"cannot analyze textures ({why}) — manual review required")
    worst = max(ratios)
    if worst < lo:
        return Classification(key, "skin_free",
                              f"max skin-pixel ratio {worst:.3f} < {lo}", worst)
    if worst > hi:
        return Classification(key, "convert",
                              f"max skin-pixel ratio {worst:.3f} > {hi} — embedded skin likely", worst)
    return Classification(
        key, "ambiguous",
        f"skin-pixel ratio {worst:.3f} inside ambiguity band [{lo},{hi}] — manual review", worst)


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
