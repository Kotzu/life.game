# Acceptance Runbook

Operator procedure to produce the acceptance evidence (brief §21) on the Windows
workstation (`D:\FiveM-AI\Sandbox\kotzu_trophy_room`). Every test maps to a tracker row
in `validation-matrix.md`; update that file as evidence lands. **Never deploy to
`E:\FiveMserver\server` before every row is PASS.**

## 0. Prerequisites

1. Sandbox txAdmin/FXServer with: `oxmysql`, `qb-core`, `rcore_clothing`, qb-target or
   ox_target, and this repo's `resources/[kotzu]` folder.
2. MySQL database; migrations apply automatically on first `ensure kotzu_trophy_room`.
3. `setr` nothing needed; grant yourself the admin ace in `server.cfg`:
   `add_ace group.admin kotzu.trophy.admin allow` (and `kotzu.archproof`).
4. Screenshot tool (F8 `screenshot` or ShareX); a screen recorder for the final video.
5. Create `captures/` in the project root (git-ignored) and drop all evidence there,
   named `T<id>_<short>.png`.

## 1. Architecture proof (locks ADR-001)

```
ensure kotzu_arch_proof
/archproof run          # follow on-screen screenshot checkpoints
```
Attach `kotzu_arch_proof/arch_proof_results.json` + checkpoint screenshots to the ADR.
Expected: A1/A2 SKIPPED-or-FAIL, B1/B2/B5/B6 PASS, B3/C1 `NOT_YET_STREAMED` (pass after
step 2), N1 INFO.

## 2. Build mannequin assets (pipeline, workstation)

1. Export freemode assets with CodeWalker as XML into `tools/mannequin_pipeline/extracted/`
   (+ PNG texture dumps into `extracted/_png/`). Never commit these.
2. `pip install pillow`, copy `config.example.json` → `config.json`, set paths + build.
3. Run: `scan` → `classify` → resolve `manual_review_queue.json` → `convert` → `export`
   → `build-manifest` → `validate` → `report-coverage`.
4. Do the manual art pass on `blender_src/*.blend` heads (modeling spec), re-`export`.
5. `ensure kotzu_mannequin_assets`, re-run `/archproof run` → B3/C1 must flip to PASS.

## 3. Acceptance tests T1–T20

| T | Procedure | Evidence |
|---|---|---|
| T1/T2 | `ensure kotzu_trophy_room`; `/kmq:spawn_male`, `/kmq:spawn_female`; orbit camera, dark room + daylight | screenshots of head/hands/neck close-ups, both genders |
| T3 | `/kmq:cycle_outfits` through the full matrix, both genders; any skin = FAIL, any refusal must show the explicit blocker message | one screenshot per matrix entry |
| T4 | `/kmq:cycle_poses` ×7 per gender; harness prints stability + foot-slide check; then `/kmq:refresh` and re-verify pose survives re-stream | console log + screenshots |
| T5 | Dress your character via rcore; `/trophyroom` → Mannequin → "My current outfit" → place | screenshot mannequin vs player side by side |
| T6 | `/kmq:probe_clothing`; if `getSavedOutfits` resolved, place with "Saved outfit…" | console output + screenshot; if unsupported, record capability map as evidence of explicit unsupport |
| T7 | Wear hat+glasses+mask+bag+armor+decal, capture to mannequin | screenshot each prop visible |
| T8 | `/kmq:testshell a`; place 2 mannequins + 1 weapon stand inside | screenshot |
| T9 | `restart kotzu_trophy_room`, then full server restart; re-enter shell | screenshots showing identical layout; `/kmq:registry_stats` before/after |
| T10 | Second client in same bucket/room; compare | both clients' screenshots of same display |
| T11 | Client A `/kmq:testshell a`, client B `/kmq:testshell b`; place in A | screenshot B seeing nothing; `/kmq:debug` on both |
| T12 | Owner: move/remove OK. Visitor (non-owner, non-admin): attempt move/remove → NOT_ALLOWED | chat screenshots |
| T13 | Stand at spawn radius edge, walk in/out ×10, `/kmq:debug` each time — spawned count stable, no duplicate peds | console log |
| T14 | Manually corrupt one row's outfit JSON in DB (sandbox only), relog | screenshot of explicit refusal/base-plastic + console error, NOT human skin |
| T15 | Verify `docs/custom-clothing-integration-guide.md` + pipeline exist | n/a (repo) |
| T16 | Run one addon garment (any free clothing pack) through the pipeline per the guide | pipeline reports + in-game screenshot |
| T17 | Place a tinted weapon with attachments (`/kmq:weapon_tx_test` T18d path or UI) | screenshot showing tint + components |
| T18 | `/kmq:weapon_tx_test` — all checks PASS; `tests/weapon_tx_results.json` saved | JSON file |
| T19 | Performance procedure in `performance-report.md` (resmon 0/1/10/25/50 displays, two clients, both buckets) | filled-in report tables |
| T20 | Record 60–120 s video: walk-through, outfit copy, pose change, try-on, weapon retrieve | video file |

## 4. Sign-off

1. All rows in `validation-matrix.md` PASS with evidence paths.
2. `coverage_report.md` shows the agreed coverage (100% of default clothing for the
   server's game build, or an explicitly accepted subset).
3. Commit evidence-file paths (not binaries) + updated matrix; tag `v1.0.0-accepted`.
4. Only then copy `resources/[kotzu]` to the live server, `Config.DevCommands = false`.
