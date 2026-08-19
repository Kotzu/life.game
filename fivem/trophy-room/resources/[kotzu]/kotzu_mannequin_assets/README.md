# kotzu_mannequin_assets

Streams the `mannequin` addon-clothing collection onto the original freemode peds
(ADR-001 Candidate B+C) and ships `mannequin_manifest.json`, the single source of
truth mapping garments to their skin status / converted twins.

## Contents

- `meta/*.meta` — `SHOP_PED_APPAREL_META_FILE` registrations declaring the
  `mannequin` DLC collection for `mp_m_freemode_01` / `mp_f_freemode_01`.
- `stream/` — built drawables/textures named
  `mp_[mf]_freemode_01_mannequin^<slug>_<idx>_u.ydd` (+ `.ytd`), produced by
  `tools/mannequin_pipeline` on the workstation. **Never commit these binaries.**
- `mannequin_manifest.json` — written by `build-manifest`. Version 0 (the committed
  seed) means "assets not built"; the trophy-room resource then refuses mannequin
  spawns with an explicit `MANIFEST_NOT_BUILT` error instead of showing human skin.

## Verification

After building + `ensure kotzu_mannequin_assets`, run `/archproof run` — tests B3/C1
flip from `NOT_YET_STREAMED` to `PASS` when the collection streams correctly.
