# Administrator Guide

## Permissions model

| Role | How granted | Capabilities |
|---|---|---|
| Owner | placed the display (citizenid match) | everything on own displays |
| Co-owner | housing resolver reports `coOwner` for the scope | manage/remove in that scope |
| Job grant | per-display `permissions = { job, grade, jobCanManage, jobCanRemove }` | as flagged |
| Admin | ace `kotzu.trophy.admin` or QBCore admin | everything, everywhere |
| Visitor | default | inspect, preview, try-on (config), equip only if `visitorEquip` |

Config switches: `Interaction.AllowVisitorTryOn`, `TryOnSeconds`, `AllowVisitorEquip`.

## Commands (DevCommands=true; server harness also needs admin ace)

| Command | Side | Purpose |
|---|---|---|
| `/trophyroom` (F7) | client | placement wizard |
| `/archproof run` | client | ADR proof suite (kotzu_arch_proof) |
| `/kmq:spawn_male` `/kmq:spawn_female` `/kmq:spawn_dressed` | client | test mannequins |
| `/kmq:cycle_outfits` `/kmq:cycle_components <id>` `/kmq:cycle_poses` | client | §6/§10 matrices |
| `/kmq:show_indexes` | client | collection/local indexes of your outfit |
| `/kmq:reload_manifest` | client | reload manifest client+server |
| `/kmq:refresh` `/kmq:debug` `/kmq:sim_reconnect` | client | streaming diagnostics |
| `/kmq:probe_clothing` | client | rcore capability map |
| `/kmq:demo_layout` | client | populate the current room with Config.DemoLayout |
| `/kmq:case_fit <weapon>` | client | measure a weapon's rotation radius vs each case style's clearance |
| `/kmq:testshell a|b` `/kmq:leaveshell` | server | test shells + routing buckets |
| `/kmq:validate_db` | server | DB/cache/lock consistency |
| `/kmq:weapon_tx_test` | server | duplication/rollback test suite |
| `/kmq:registry_stats` `/kmq:bridges` | server | registry + bridge state |

## Operational runbooks

- **Stuck weapon transaction** (`/kmq:validate_db` reports a stale lock): the startup
  recovery closes stranded locks automatically on restart. A `weapon_recovery_credit`
  audit row means a player is owed an item — return it manually and note the audit id.
- **Player claims lost weapon**: query `kotzu_display_audit` by citizenid; every place/
  retrieve/failure is logged with idempotency key and serial.
- **Manifest/asset update**: deploy assets → restart both resources →
  `/kmq:reload_manifest`. Existing displays keep working (append-only indexes); any
  display whose garments became reclassified as incompatible renders base plastic with
  an explicit error rather than skin.
- **Removing someone's display**: admins see full options on any display via target.
- **Disable harness for production**: `Config.DevCommands = false`.

## Monitoring

- Audit trail: `kotzu_display_audit`.
- Consistency: `/kmq:validate_db` (cache vs DB vs locks).
- Performance: follow `docs/performance-report.md` procedure after content changes.
