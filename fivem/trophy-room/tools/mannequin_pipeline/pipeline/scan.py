"""scan — walk extracted/ and build the drawable/texture catalog."""

from __future__ import annotations

from collections import defaultdict
from pathlib import Path

from .model import (DrawableRecord, TEXTURE_RE, canonical_stems,
                    parse_drawable_name, record_to_dict, save_json)

DRAWABLE_SUFFIXES = (".ydd.xml", ".ydd")
TEXTURE_SUFFIXES = (".ytd.xml", ".ytd")


def _stem(path: Path) -> str:
    name = path.name.lower()
    for suf in DRAWABLE_SUFFIXES + TEXTURE_SUFFIXES:
        if name.endswith(suf):
            return name[: -len(suf)]
    return path.stem.lower()


def scan(extracted_dir: Path, build_dir: Path) -> dict:
    records: dict[str, DrawableRecord] = {}
    textures = defaultdict(list)
    skipped = []

    for path in sorted(extracted_dir.rglob("*")):
        if not path.is_file():
            continue
        name = path.name.lower()
        stem = _stem(path)
        # CodeWalker exports carry the plain in-folder file name; the model/
        # collection identity lives in the RPF folder name (the on-disk parent
        # when exported folder-by-folder). Try the stem as-is, then folder^stem.
        folder = path.parent.name
        if name.endswith(DRAWABLE_SUFFIXES):
            parsed = None
            for cand in canonical_stems(stem, folder):
                parsed = parse_drawable_name(cand)
                if parsed:
                    break
            if not parsed:
                skipped.append(str(path))
                continue
            rec = DrawableRecord(source_path=str(path), **parsed)
            # prefer .ydd.xml over .ydd when both exist
            prev = records.get(rec.key)
            if prev is None or path.name.lower().endswith(".ydd.xml"):
                if prev is not None:
                    rec.texture_count = prev.texture_count
                    rec.texture_names = prev.texture_names
                records[rec.key] = rec
        elif name.endswith(TEXTURE_SUFFIXES):
            m = None
            matched_stem = stem
            for cand in canonical_stems(stem, folder):
                m = TEXTURE_RE.match(cand)
                if m:
                    matched_stem = cand
                    break
            if m:
                gender = "male" if "_m_" in m.group("model") else "female"
                tex_key = (gender, m.group("collection") or "",
                           m.group("slug"), int(m.group("idx")))
                textures[tex_key].append(matched_stem)
            else:
                skipped.append(str(path))

    # attach texture counts
    for rec in records.values():
        tk = (rec.gender, rec.collection, rec.component_slug, rec.local_drawable)
        texs = sorted(set(textures.get(tk, [])))
        rec.texture_names = texs
        rec.texture_count = len(texs)

    catalog = {
        "schema": "kotzu_scan_catalog/1",
        "counts": {
            "drawables": len(records),
            "skipped": len(skipped),
        },
        "drawables": {k: record_to_dict(r) for k, r in sorted(records.items())},
        "skipped": skipped,
    }
    save_json(build_dir / "scan_catalog.json", catalog)
    return catalog
