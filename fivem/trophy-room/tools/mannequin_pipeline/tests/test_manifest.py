import json
from pathlib import Path

import pytest

from pipeline.manifest import build_manifest, BODY_RESERVED
from pipeline.model import save_json
from pipeline.reports import report

CFG = {"collection_name": "mannequin", "game_build": 3258,
       "assets_resource_dir": "assets"}


def rec(comp, slug, gender="male", coll="", idx=0):
    return {
        "gender": gender, "model": "mp_m_freemode_01", "collection": coll,
        "component_slug": slug, "component_id": comp, "local_drawable": idx,
        "is_prop": False, "race_suffix": "u", "source_path": f"x/{slug}_{idx}",
        "texture_count": 1, "texture_names": [f"t_{slug}_{idx}"],
    }


@pytest.fixture
def build(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    b = tmp_path / "build"
    catalog = {"drawables": {
        "male:comp3::0": rec(3, "uppr", idx=0),
        "male:comp11::4": rec(11, "jbib", idx=4),
        "male:comp11::5": rec(11, "jbib", idx=5),
        "male:comp4::2": rec(4, "lowr", idx=2),
    }}
    classification = {"items": {
        "male:comp3::0": {"effective": "body_skin"},
        "male:comp11::4": {"effective": "convert"},
        "male:comp11::5": {"effective": "skin_free"},
        "male:comp4::2": {"effective": "ambiguous"},
    }}
    save_json(b / "scan_catalog.json", catalog)
    save_json(b / "classification.json", classification)
    save_json(b / "conversion_state.json",
              {"done": {"male:comp11::4": "deadbeef"}})
    return b


def test_manifest_statuses(build, tmp_path):
    mpath = tmp_path / "assets" / "mannequin_manifest.json"
    m = build_manifest(build, CFG, mpath)
    g = m["genders"]["male"]
    assert g["garments"]["male:comp11::5"]["status"] == "skin_free"
    assert g["garments"]["male:comp4::2"]["status"] == "pending_review"
    conv = g["garments"]["male:comp11::4"]
    assert conv["status"] == "converted"
    assert conv["converted"]["collection"] == "mannequin"
    assert conv["converted"]["drawable"] >= BODY_RESERVED
    assert "0" in m["allocations"]["male"]["3"] or m["allocations"]["male"]["3"]


def test_allocation_is_stable_across_rebuilds(build, tmp_path):
    mpath = tmp_path / "assets" / "mannequin_manifest.json"
    m1 = build_manifest(build, CFG, mpath)
    idx1 = m1["genders"]["male"]["garments"]["male:comp11::4"]["converted"]["drawable"]

    # add a new converted garment, rebuild — old index must not move
    catalog = json.loads((build / "scan_catalog.json").read_text())
    catalog["drawables"]["male:comp11::9"] = rec(11, "jbib", idx=9)
    save_json(build / "scan_catalog.json", catalog)
    cls = json.loads((build / "classification.json").read_text())
    cls["items"]["male:comp11::9"] = {"effective": "convert"}
    save_json(build / "classification.json", cls)
    state = json.loads((build / "conversion_state.json").read_text())
    state["done"]["male:comp11::9"] = "cafe"
    save_json(build / "conversion_state.json", state)

    m2 = build_manifest(build, CFG, mpath)
    idx2_old = m2["genders"]["male"]["garments"]["male:comp11::4"]["converted"]["drawable"]
    idx2_new = m2["genders"]["male"]["garments"]["male:comp11::9"]["converted"]["drawable"]
    assert idx2_old == idx1
    assert idx2_new != idx1
    assert m2["version"] == m1["version"] + 1


def test_coverage_report(build, tmp_path):
    mpath = tmp_path / "assets" / "mannequin_manifest.json"
    build_manifest(build, CFG, mpath)
    out = report(build, CFG, mpath)
    # 3 garments total (uppr is body): converted + skin_free supported, ambiguous not
    assert out["totals"]["total"] == 3
    assert out["totals"]["supported"] == 2
    assert out["coverage_pct"] == pytest.approx(66.67, abs=0.01)
    assert Path("coverage_report.md").exists()
    assert Path("conversion_report.json").exists()
