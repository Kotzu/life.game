# Installation Guide

## Requirements

- FXServer (recent artifact, game build with collection natives — b2189+; project
  developed against b3258 conventions)
- MySQL/MariaDB + `oxmysql`
- Framework: **Qbox (`qbx_core`) — first-class, verified against its source** — or
  QBCore (`qb-core`); works standalone with reduced identity features. When both
  are present (Qbox's qb-core compat layer), the qbox bridge wins by priority.
- Optional: `illenium-appearance` (saved outfits read server-side from
  `player_outfits` — the standard on Qbox) or `rcore_clothing` (capability-probed),
  `ox_target` or `qb-target`, `ox_inventory` or `qb-inventory` (required for
  weapon displays)

### Qbox stack (recommended)

```
ensure oxmysql
ensure ox_lib
ensure qbx_core
ensure ox_inventory
ensure ox_target
ensure illenium-appearance
ensure kotzu_mannequin_assets
ensure kotzu_trophy_room
```
All five bridges (framework/clothing/target/inventory/housing) auto-detect this
stack; notifications go through qbx_core server-side and ox_lib client-side.

## Steps

1. **Database**: create/choose a database; oxmysql configured as usual. Migrations run
   automatically on first start of `kotzu_trophy_room` (tracked in
   `kotzu_schema_migrations`; all statements idempotent). To pre-apply manually, run
   the files in `kotzu_trophy_room/sql/` in order.
2. **Resources**: copy `resources/[kotzu]` into your resources folder. Ensure order:
   ```
   ensure oxmysql
   ensure qb-core            # if used
   ensure rcore_clothing     # if used
   ensure kotzu_mannequin_assets
   ensure kotzu_trophy_room
   ensure kotzu_arch_proof   # sandbox only
   ```
3. **Permissions** (`server.cfg`):
   ```
   add_ace group.admin kotzu.trophy.admin allow
   add_ace group.admin kotzu.archproof allow   # sandbox only
   ```
4. **Assets**: build the mannequin collection with `tools/mannequin_pipeline` (see its
   README) and deploy the produced `stream/` + `mannequin_manifest.json` into
   `kotzu_mannequin_assets`. Until then the resource runs but refuses mannequin
   placement with `MANIFEST_NOT_BUILT` (weapon/prop displays still work).
5. **Config**: review `kotzu_trophy_room/shared/config.lua` — streaming radii, limits,
   rate limits, poses, platforms, test shells, `DevCommands` (set **false** on live),
   weapon stand/case models.
6. **Housing integration** (optional now, recommended later): from your housing
   resource call the client exports on room enter/exit and register a server resolver —
   contract documented in `bridge/housing/generic.lua`.
7. Verify with the acceptance runbook before promoting to the live server.

## Upgrading

- New pipeline runs only ever append manifest indexes; restart both `[kotzu]`
  resources after deploying new assets, then `/kmq:reload_manifest`.
- Schema changes ship as new numbered `sql/` files + a `MIGRATIONS` list entry;
  outfit payload changes bump `KTR.Const.OUTFIT_SCHEMA` with a migration in
  `shared/schemas.lua` (`MigrateOutfit`).
