# Headless Verification Report

What could be verified WITHOUT a FiveM client, executed in the cloud dev
environment on 2026-08-23. This complements (does not replace) the in-game
acceptance suite.

## 1. FXServer-environment simulation — 32/32 checks PASS

`tools/fxsim/` shims the FXServer server-side natives (events, scheduler,
players, buckets, aces, resource files) and oxmysql (over the `mariadb` CLI),
then loads the **real, unmodified** trophy-room server scripts against a
**real MariaDB 10.11** and drives the RPC surface end to end:

| Scenario | Result |
|---|---|
| S1 boot: migrations apply (3/3 tracked), repository loads | PASS |
| S2 place bare mannequin: persisted, broadcast, owner not leaked to clients | PASS |
| S3 outfit against manifest v0 → refused `MANIFEST_NOT_BUILT` | PASS |
| S4 visitor update/delete denied, admin allowed, capability shape | PASS |
| S5 bad type / NaN transform / non-whitelisted pose rejected | PASS |
| S6 place rate limit triggers within the window | PASS |
| S7 weapon tx: place removes exact item (serial persisted), **idempotent replay returns same uid**, retrieve returns item exactly once, second retrieve refused, zero duplication | PASS |
| S8 missing item → `ITEM_MISSING`, lock failed-closed | PASS |
| S9 stranded `item_removed` lock → `recovered` + audit credit row | PASS |
| S10 owner delete, double-delete `NOT_FOUND`, scope listing | PASS |
| S11 `admin:validateDb` reports zero inconsistencies | PASS |

Reproduce: start MariaDB, then `cd tools/fxsim && lua5.4 run.lua`
(env `FXSIM_MYSQL_SOCKET`, `FXSIM_MYSQL_DB`). Exit code 0 = all pass.
Raw run output: `tools/fxsim/last_run.txt`.

SQL semantics were additionally proven directly: `INSERT IGNORE` affected-rows
gate (1 then 0), soft-delete-as-lock (`ROW_COUNT()` 1 then 0), idempotent
double-apply of every migration file.

## 2. Sollumz API verification — against real source + real Blender

Sollumz 2.9 cloned from GitHub; `szio` 1.3.0 (its IO library) installed from
PyPI; Blender 4.2.0 and 5.0.1 as the `bpy` Python module.

| Assumption in pipeline scripts | Verdict |
|---|---|
| `bpy.ops.sollumz.import_assets(directory=…, files=[{name}])` | **CONFIRMED** — exact operator id and property names (`sollumz_operators.py`) |
| `bpy.ops.sollumz.export_assets(directory=…)` | **CONFIRMED**, improved: pass `direct_export=True` for headless runs |
| `create_shader("ped_default.sps")` | **CONFIRMED** — `ydr/shader_materials.py:1321`, signature `create_shader(filename, in_place_material=None)`; `ped_default.sps` present in szio `ShaderManager` (27 ped shaders enumerated); bare `"ped_default"` (no `.sps`) is NOT found — the `.sps` suffix in our code is required and correct |
| `from sollumz.ydr.shader_materials import create_shader` | **GAP FOUND & FIXED** — module name is install-dependent (`Sollumz` folder addon vs `bl_ext.<repo>.sollumz[_dev]` extension); replaced with dynamic module resolution |
| legacy fallbacks `sollumz.importydd` / `exportydd` | not present in Sollumz 2.9 (kept as harmless fallbacks for older installs) |

Execution test: `create_shader` imported and executed under headless `bpy`; it
reached Sollumz's registered-property layer (`sollum_type`), which requires a
full addon registration that the standalone `bpy` wheel cannot complete
(extension bootstrap expects Blender's addon environment; Blender 5.0 also
predates Sollumz support). Conclusion: **full conversion jobs must run inside
real Blender 4.2+ with Sollumz installed** — exactly how `pipeline convert`
invokes them (`blender --background --addons sollumz`). This limitation is
environmental, not a defect in the job scripts.

## 3. What this does NOT prove

No rendering, no game assets, no client natives, no streaming behavior — the
in-game acceptance suite (T1–T20, `docs/acceptance-runbook.md`) remains the
only source of those claims.
