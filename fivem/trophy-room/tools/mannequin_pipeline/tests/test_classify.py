import json
import os
from pathlib import Path

import pytest

from pipeline import classify as classify_mod
from pipeline.classify import classify, classify_record
from pipeline.model import save_json

CFG = {"ambiguous_band": [0.015, 0.12], "texture_png_dir": "does/not/exist"}


def rec(comp, slug, is_prop=False, gender="male", coll="", idx=0, texs=None):
    return {
        "gender": gender, "model": "mp_m_freemode_01", "collection": coll,
        "component_slug": slug, "component_id": comp, "local_drawable": idx,
        "is_prop": is_prop, "race_suffix": "u", "source_path": "x",
        "texture_count": len(texs or []), "texture_names": texs or [],
    }


def test_body_skin_components_are_body_skin(tmp_path):
    for comp, slug in ((0, "head"), (2, "hair"), (3, "uppr"), (5, "hand"), (7, "teef")):
        c = classify_record(rec(comp, slug), CFG, tmp_path)
        assert c.category == "body_skin", slug


def test_decl_task_are_skin_free(tmp_path):
    assert classify_record(rec(10, "decl"), CFG, tmp_path).category == "skin_free"
    assert classify_record(rec(9, "task"), CFG, tmp_path).category == "skin_free"


def test_props_are_skin_free(tmp_path):
    c = classify_record(rec(0, "p_head", is_prop=True), CFG, tmp_path)
    assert c.category == "skin_free"


def test_analyze_component_without_textures_is_ambiguous(tmp_path):
    c = classify_record(rec(11, "jbib", texs=["mp_m_freemode_01^jbib_diff_000_a_uni"]),
                        CFG, tmp_path)
    assert c.category == "ambiguous"  # no PNGs / no Pillow -> never guess


def test_manual_resolution_wins(tmp_path):
    prior = {"category": "ambiguous", "reason": "x", "resolution": "convert"}
    c = classify_record(rec(11, "jbib"), CFG, tmp_path, prior)
    assert c.effective == "convert"


@pytest.mark.skipif(not classify_mod.HAVE_PIL, reason="Pillow not installed")
def test_skin_pixel_ratio_detects_skin(tmp_path):
    from PIL import Image
    skin = Image.new("RGBA", (32, 32), (224, 172, 138, 255))
    p = tmp_path / "skin.png"
    skin.save(p)
    r = classify_mod.skin_pixel_ratio(p)
    assert r is not None and r > 0.9


def test_classify_end_to_end_writes_queue(tmp_path, monkeypatch):
    build = tmp_path / "build"
    catalog = {
        "schema": "kotzu_scan_catalog/1",
        "drawables": {
            "male:comp3::0": rec(3, "uppr"),
            "male:comp11::0": rec(11, "jbib",
                                  texs=["mp_m_freemode_01^jbib_diff_000_a_uni"]),
        },
    }
    save_json(build / "scan_catalog.json", catalog)
    monkeypatch.chdir(tmp_path)
    out = classify(build, CFG)
    assert out["items"]["male:comp3::0"]["effective"] == "body_skin"
    assert out["items"]["male:comp11::0"]["effective"] == "ambiguous"
    queue = json.loads(Path("manual_review_queue.json").read_text())
    assert queue["unresolved"] == 1

    # resolve it and re-run: resolution must be honored and queue drained
    queue["items"][0]["resolution"] = "skin_free"
    Path("manual_review_queue.json").write_text(json.dumps(queue))
    out2 = classify(build, CFG)
    assert out2["items"]["male:comp11::0"]["effective"] == "skin_free"
    queue2 = json.loads(Path("manual_review_queue.json").read_text())
    assert queue2["unresolved"] == 0
