# Validation Matrix (acceptance §21)

Single source of truth for project completion. **Status legend:**
`PASS` (evidence attached) · `FAIL` · `PENDING-INGAME` (implemented + statically
validated here; requires a FiveM client to produce evidence) · `BLOCKED`.

No row may be flipped to PASS without an evidence path in the last column.

| # | Test | Status | Evidence |
|---|---|---|---|
| T1 | Male mannequin fully faceless and plastic | PENDING-INGAME | — |
| T2 | Female mannequin fully faceless and plastic | PENDING-INGAME | — |
| T3 | No human skin across default clothing matrix | PENDING-INGAME | — |
| T4 | ≥6 stable poses, both genders | PENDING-INGAME | — |
| T5 | Current rcore outfit copies to mannequin | PENDING-INGAME | — |
| T6 | Saved outfit selectable (where rcore supports) | PENDING-INGAME | — |
| T7 | Hat/glasses/mask/bag/armor/accessory correct | PENDING-INGAME | — |
| T8 | Placement works in a shell | PENDING-INGAME | — |
| T9 | Persistence across server/resource restart | PENDING-INGAME | — |
| T10 | Two clients see identical display state | PENDING-INGAME | — |
| T11 | Routing buckets do not leak displays | PENDING-INGAME | — |
| T12 | Owner can move/delete; visitor cannot | PENDING-INGAME | — |
| T13 | Streaming never duplicates entities | PENDING-INGAME | — |
| T14 | Invalid clothing data → safe explicit error | PENDING-INGAME | — |
| T15 | Custom clothing conversion docs + tool exist | PASS | `docs/custom-clothing-integration-guide.md`, `tools/mannequin_pipeline/` (16 unit tests green) |
| T16 | Test addon garment passes conversion pipeline | PENDING-INGAME | — (pipeline dry-run validated headlessly) |
| T17 | Weapon display preserves tint/skin/attachments | PENDING-INGAME | — |
| T18 | Weapon place/retrieve cannot duplicate | PENDING-INGAME | harness: `/kmq:weapon_tx_test` → `tests/weapon_tx_results.json` |
| T19 | Actual performance numbers recorded | PENDING-INGAME | template: `docs/performance-report.md` |
| T20 | Final screenshots + video from FiveM | PENDING-INGAME | — |

## Static validation already performed (this repo, headless)

- All 34 Lua files parse clean (luaparser, Lua 5.4-compatible syntax).
- NUI JavaScript passes `node --check`.
- Pipeline: 16/16 pytest cases pass; full CLI smoke test executed end-to-end on
  synthetic inputs (caught + fixed one per-gender counting bug in coverage reporting).
- `validate` correctly fails (exit 1) while mannequin body assets are missing —
  the "honest failure" path works.
