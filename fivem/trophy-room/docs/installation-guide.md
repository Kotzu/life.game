# Installation Guide

## Requirements

- FXServer (recent artifact, game build with collection natives — b2189+; project
  developed against b3258 conventions)
- MySQL/MariaDB + `oxmysql`
- QBCore (`qb-core`); works standalone with reduced identity features
- Optional: `rcore_clothing` (outfit snapshots/saved outfits), `qb-target` or
  `ox_target`, `qb-inventory` or `ox_inventory` (required for weapon displays)

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
