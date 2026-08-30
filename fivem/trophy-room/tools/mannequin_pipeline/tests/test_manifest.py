import json
from pathlib import Path

import pytest

from pipeline.manifest import build_manifest
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
    # base pieces keep their SOURCE index — that is how the files are named
    assert conv["converted"]["drawable"] == 4
    assert g["body"]["3"]["variants"][":0"] == 0


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
    assert idx2_new == 9  # base piece: file named by its source index
    assert m2["version"] == m1["version"] + 1


def test_dlc_pieces_get_allocated_indexes(build, tmp_path):
    # a DLC-collection garment must get a stable index >= 16, matching the
    # file-name allocator convert uses
    catalog = json.loads((build / "scan_catalog.json").read_text())
    catalog["drawables"]["male:comp6:beach:0"] = rec(6, "feet", coll="beach", idx=0)
    save_json(build / "scan_catalog.json", catalog)
    cls = json.loads((build / "classification.json").read_text())
    cls["items"]["male:comp6:beach:0"] = {"effective": "convert"}
    save_json(build / "classification.json", cls)
    state = json.loads((build / "conversion_state.json").read_text())
    state["done"]["male:comp6:beach:0"] = "beef"
    save_json(build / "conversion_state.json", state)

    mpath = tmp_path / "assets" / "mannequin_manifest.json"
    m = build_manifest(build, CFG, mpath)
    got = m["genders"]["male"]["garments"]["male:comp6:beach:0"]["converted"]["drawable"]
    assert got == 16
    # and it is persisted in the shared alloc file convert reads
    alloc = json.loads((build / "manifest_alloc.json").read_text())
    assert alloc["male"]["comp6"]["beach:0"] == 16


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
