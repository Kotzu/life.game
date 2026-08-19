# Custom / Addon Clothing Integration Guide

How to make any addon clothing pack mannequin-compatible (acceptance T15/T16).

## Concept

Addon clothing attaches to the freemode models as a named **collection** (its DLC
name). The mannequin system addresses garments by `(componentId, collectionName,
localDrawable)`, so addon garments work exactly like base-game ones once they are in
the catalog: skin-free garments pass straight through; skin-bearing ones get converted
twins inside the `mannequin` collection.

## Step by step

1. **Locate the pack's drawables.** In the addon resource's `stream/` you'll find
   files like `mp_m_freemode_01_<dlcname>^jbib_004_u.ydd`. The `<dlcname>` is the
   collection name the game (and this system) sees.
2. **Export for the pipeline.** Open the pack's `.ydd`/`.ytd` in CodeWalker, export as
   XML + PNG dumps into `tools/mannequin_pipeline/extracted/<packname>/`
   (any subfolder works — the scanner recurses).
3. **Run the incremental pipeline** (only new inputs are processed):
   ```
   python -m pipeline scan
   python -m pipeline classify        # new items classified; ambiguous -> review queue
   # edit manual_review_queue.json resolutions if any, re-run classify
   python -m pipeline convert
   python -m pipeline export
   python -m pipeline build-manifest  # append-only: existing indexes never move
   python -m pipeline validate && python -m pipeline report-coverage
   ```
4. **Deploy**: the converted twins land in `kotzu_mannequin_assets/stream/`; the
   updated `mannequin_manifest.json` ships with the same resource. `restart
   kotzu_mannequin_assets kotzu_trophy_room`, then in game `/kmq:reload_manifest`.
5. **Validate in game**: wear the addon garments, `/kmq:spawn_dressed`, screenshot.
   Update `clothing-compatibility-report.md`.

## Rules

- Never commit the pack's binaries or your conversions of them to git (license +
  repo-hygiene: `.gitignore` already blocks `ydd/ytd/...`).
- If `classify` marks a garment ambiguous, decide it in `manual_review_queue.json` —
  the system will refuse to display it until you do. That refusal is the feature.
- Re-running `build-manifest` bumps the manifest version; already-placed mannequins
  keep working because allocation is append-only.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Garment shows `unknown` blocker in `/kmq:debug` | pack not scanned — steps 2–3 |
| Converted twin invisible in game | export naming: must be `mp_[mf]_freemode_01_mannequin^<slug>_<idx>_u.ydd` and match the manifest's allocated index; run `pipeline validate` |
| Blender job `ambiguous: materials could not be classified` | add the pack's texture naming tokens to the job `hints.extra_skin_tokens` or resolve via review queue |
| Everything refused after adding a pack | manifest not redeployed/reloaded — step 4 |
