import json
from pathlib import Path

import pytest

from pipeline.reference import build_reference, crosscheck
from pipeline.model import save_json


DUMP = [
    {
        "LastUpdateDlcName": "basegame",
        "DlcCollectionName": "mp_m_freemode_01",
        "PedName": "mp_m_freemode_01",
        "ComponentVariations": [
            # jbib 0 with 2 textures, jbib 1 with 1 texture
            {"ComponentId": 11, "RelativeCollectionDrawableId": 0, "DrawableId": 0, "TextureId": 0},
            {"ComponentId": 11, "RelativeCollectionDrawableId": 0, "DrawableId": 0, "TextureId": 1},
            {"ComponentId": 11, "RelativeCollectionDrawableId": 1, "DrawableId": 1, "TextureId": 0},
            # uppr (body) 0
            {"ComponentId": 3, "RelativeCollectionDrawableId": 0, "DrawableId": 0, "TextureId": 0},
        ],
        "Props": [
            {"ComponentId": 0, "RelativeCollectionDrawableId": 0, "DrawableId": 0, "TextureId": 0},
        ],
    },
    {
        "LastUpdateDlcName": "mpheist3",
        "DlcCollectionName": "mp_heist3",
        "PedName": "mp_m_freemode_01",
        "ComponentVariations": [
            {"ComponentId": 11, "RelativeCollectionDrawableId": 0, "DrawableId": 100, "TextureId": 0},
        ],
        "Props": [],
    },
]


@pytest.fixture
def ref_path(tmp_path):
    dump_path = tmp_path / "dump.json"
    dump_path.write_text(json.dumps(DUMP))
    out = tmp_path / "reference.json"
    build_reference(dump_path, out, source_commit="abc123")
    return out


def test_build_reference_aggregates(ref_path):
    ref = json.loads(ref_path.read_text())
    male = ref["genders"]["male"]
    base = male["collections"][""]  # base collection normalized to ''
    assert base["components"]["11"] == {"0": 2, "1": 1}
    assert base["components"]["3"] == {"0": 1}
    assert base["props"]["0"] == {"0": 1}
    assert male["collections"]["mp_heist3"]["components"]["11"] == {"0": 1}
    assert male["totals"]["garment_drawables"] == 3  # jbib 0,1 + heist3 jbib 0
    assert male["totals"]["body_drawables"] == 1
    assert male["totals"]["prop_drawables"] == 1
    assert ref["source"]["commit"] == "abc123"


def rec(comp, slug, coll="", idx=0, texs=1, is_prop=False):
    return {
        "gender": "male", "model": "mp_m_freemode_01", "collection": coll,
        "component_slug": slug, "component_id": comp, "local_drawable": idx,
        "is_prop": is_prop, "race_suffix": "u", "source_path": "x",
        "texture_count": texs, "texture_names": [f"t{i}" for i in range(texs)],
    }


def test_crosscheck(ref_path, tmp_path):
    build = tmp_path / "build"
    save_json(build / "scan_catalog.json", {"drawables": {
        "male:comp11::0": rec(11, "jbib", idx=0, texs=2),      # matches
        "male:comp11::1": rec(11, "jbib", idx=1, texs=3),      # texture mismatch
        "male:comp11:romanian_police:0": rec(11, "jbib", coll="romanian_police"),  # unknown
        # base uppr 0, heist3 jbib 0, prop -> missing locally
    }})
    out = crosscheck(build, ref_path)
    s = out["summary"]
    assert s["matched"] == 2
    assert s["unknown"] == 1
    assert s["texture_mismatches"] == 1
    assert s["missing"] == 3  # uppr:0, mp_heist3 jbib:0, prop 0:0
    assert (build / "crosscheck_report.json").exists()
