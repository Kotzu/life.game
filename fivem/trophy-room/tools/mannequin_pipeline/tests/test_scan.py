import json
from pathlib import Path

import pytest

from pipeline.model import folder_prefix, parse_drawable_name
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


# ---- folder-based exports (what CodeWalker actually writes: plain in-folder
# ---- file names, identity carried by the RPF folder name; '^' never on disk)

def test_folder_prefix():
    assert folder_prefix("mp_m_freemode_01") == "mp_m_freemode_01"
    assert folder_prefix("mp_f_freemode_01_mp_heist3") == "mp_f_freemode_01_mp_heist3"
    # prop marker '_p' is dropped (prop-ness comes from the p_* slug)
    assert folder_prefix("mp_m_freemode_01_p") == "mp_m_freemode_01"
    assert folder_prefix("mp_m_freemode_01_p_mp_heist3") == "mp_m_freemode_01_mp_heist3"
    assert folder_prefix("a_m_y_hipster_01") is None


@pytest.fixture
def extracted_folders(tmp_path):
    d = tmp_path / "extracted"
    base_m = d / "base_male" / "mp_m_freemode_01"
    base_m.mkdir(parents=True)
    (base_m / "jbib_000_u.ydd.xml").write_text("<x/>")
    (base_m / "jbib_diff_000_a_uni.ytd.xml").write_text("<x/>")
    (base_m / "uppr_000_u.ydd.xml").write_text("<x/>")
    props_m = d / "base_male" / "mp_m_freemode_01_p"
    props_m.mkdir(parents=True)
    (props_m / "p_head_002.ydd.xml").write_text("<x/>")
    dlc_f = d / "dlc" / "mp_f_freemode_01_mp_heist3"
    dlc_f.mkdir(parents=True)
    (dlc_f / "jbib_014_u.ydd.xml").write_text("<x/>")
    # a folder that isn't a freemode ped folder -> its files are skipped
    junk = d / "base_male" / "not_a_ped"
    junk.mkdir(parents=True)
    (junk / "jbib_000_u.ydd.xml").write_text("<x/>")
    return d


def test_scan_folder_layout(extracted_folders, tmp_path):
    cat = scan(extracted_folders, tmp_path / "build")
    assert cat["counts"]["drawables"] == 4
    jbib = cat["drawables"]["male:comp11::0"]
    assert jbib["model"] == "mp_m_freemode_01"
    # texture matched through the same folder-derived prefix, stored canonically
    assert jbib["texture_names"] == ["mp_m_freemode_01^jbib_diff_000_a_uni"]
    prop = cat["drawables"]["male:prop0::2"]
    assert prop["is_prop"] is True and prop["collection"] == ""
    dlc = cat["drawables"]["female:comp11:mp_heist3:14"]
    assert dlc["collection"] == "mp_heist3"
    # the non-ped folder's file was skipped, not misattributed
    assert any("not_a_ped" in s for s in cat["skipped"])
