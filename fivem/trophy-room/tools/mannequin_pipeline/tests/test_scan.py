import json
from pathlib import Path

import pytest

from pipeline.model import parse_drawable_name
from pipeline.scan import scan


def test_parse_base_drawable():
    p = parse_drawable_name("mp_m_freemode_01^uppr_003_u")
    assert p == {
        "gender": "male", "model": "mp_m_freemode_01", "collection": "",
        "component_slug": "uppr", "component_id": 3, "local_drawable": 3,
        "is_prop": False, "race_suffix": "u",
    }


def test_parse_dlc_drawable():
    p = parse_drawable_name("mp_f_freemode_01_mp_heist3^jbib_014_u")
    assert p["gender"] == "female"
    assert p["collection"] == "mp_heist3"
    assert p["component_id"] == 11
    assert p["local_drawable"] == 14


def test_parse_prop():
    p = parse_drawable_name("mp_m_freemode_01^p_head_002")
    assert p["is_prop"] is True
    assert p["component_id"] == 0
    assert p["component_slug"] == "p_head"


def test_parse_rejects_non_freemode():
    assert parse_drawable_name("a_m_y_hipster_01^uppr_000_u") is None
    assert parse_drawable_name("prop_chair_01") is None


@pytest.fixture
def extracted(tmp_path):
    d = tmp_path / "extracted"
    d.mkdir()
    (d / "mp_m_freemode_01^jbib_000_u.ydd.xml").write_text("<x/>")
    (d / "mp_m_freemode_01^jbib_diff_000_a_uni.ytd.xml").write_text("<x/>")
    (d / "mp_m_freemode_01^jbib_diff_000_b_uni.ytd.xml").write_text("<x/>")
    (d / "mp_m_freemode_01^uppr_000_u.ydd.xml").write_text("<x/>")
    (d / "garbage.txt").write_text("nope")
    return d


def test_scan_builds_catalog(extracted, tmp_path):
    build = tmp_path / "build"
    cat = scan(extracted, build)
    assert cat["counts"]["drawables"] == 2
    jbib = cat["drawables"]["male:comp11::0"]
    assert jbib["texture_count"] == 2
    on_disk = json.loads((build / "scan_catalog.json").read_text())
    assert on_disk["counts"] == cat["counts"]


def test_scan_is_deterministic(extracted, tmp_path):
    a = scan(extracted, tmp_path / "b1")
    b = scan(extracted, tmp_path / "b2")
    assert a["drawables"] == b["drawables"]
