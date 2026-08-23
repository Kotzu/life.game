# Default Clothing Compatibility Report

**Status: catalog not yet generated** — it requires the game assets on the workstation.
This document defines the catalog contract and records results once generated.
"All default clothing supported" may only ever be claimed from a generated
`coverage_report.md` where Supported == Total for both genders (brief §6).

## How the catalog is produced

1. `python -m pipeline scan` enumerates every freemode drawable/texture found in the
   CodeWalker export for the server's game build → `build/scan_catalog.json`.
2. `classify` assigns each drawable one of:
   - `body_skin` — base skin carrier, replaced by the mannequin body set;
   - `skin_free` — verified no visible skin (texture analysis under threshold);
   - `convert` — embedded skin; pipeline generates a mannequin-safe twin;
   - `ambiguous` — sent to `manual_review_queue.json`; a human decides. **Never guessed.**
3. `build-manifest` + `report-coverage` emit the machine-readable
   `conversion_report.json` and human `coverage_report.md` with the real coverage %.

## Catalog fields (per brief §6)

`gender · collection · component_id · local_drawable · texture_count ·
contains_visible_skin (skin_pixel_ratio evidence) · conversion_required ·
conversion_status (pending/converted/failed) · validation_status (in-game matrix) ·
notes`

All fields live in `conversion_report.json` items; `validation_status` is appended by
the in-game matrix run (`/kmq:cycle_outfits`) and recorded below.

## Enforcement chain (why unsupported garments can never leak skin)

1. Server refuses placement/update of outfits containing non-`skin_free`/`converted`
   garments (`validation.lua CheckOutfitCompatibility`) — including *unknown* garments
   not in the catalog at all.
2. Client plans the entire outfit before touching the ped; any blocker aborts to base
   plastic with an explicit `OUTFIT_INCOMPATIBLE` state (`client/mannequin.lua`).
3. Manifest v0 (assets not built) refuses all mannequin spawns (`MANIFEST_NOT_BUILT`).

## In-game validation matrix results (fill during T3)

| Matrix entry | Male | Female | Notes |
|---|---|---|---|
| full_suit | | | |
| police/tactical uniform | | | |
| long_sleeve | | | |
| short_sleeve | | | |
| tank_top | | | |
| exposed_torso | | | |
| long trousers | | | |
| shorts | | | |
| skirt/dress | | (f) | |
| closed shoes | | | |
| sandals/open footwear | | | |
| vest/body armor | | | |
| bag | | | |
| hat | | | |
| glasses | | | |
| mask | | | |
| decals/accessories | | | |

Current coverage: **see generated `coverage_report.md`** (none committed yet — the
committed seed manifest is v0 by design).

## Known denominators (from the committed reference catalog, 2026-08-23)

Built from the open DurtyFree metadata dump (IDs/counts only, no assets):

| Gender | Garment drawables (need classification) | Body-skin drawables (mannequin twins) | Props |
|---|---|---|---|
| Male | 1,340 | 613 | 336 |
| Female | 1,442 | 621 | 314 |

Spread over the base collection + 43 MP DLC collections per gender.
"100% default clothing coverage" therefore means, concretely: 2,782 garment
drawables classified `skin_free` or `converted`, with the two body sets built.
`python -m pipeline crosscheck` verifies a local extraction against these
numbers drawable-by-drawable.
