# Mannequin Asset Pipeline

Reproducible pipeline that turns CodeWalker-extracted freemode assets into the
`mannequin` addon-clothing collection streamed by `kotzu_mannequin_assets`:

- the **mannequin body set** (faceless head, scalp, plastic uppr/lowr/feet variants), and
- **converted twins** of skin-bearing garments (skin surfaces → mannequin plastic,
  garment textures untouched).

## Requirements (workstation)

- Python 3.10+ (`pip install pillow` optional but strongly recommended — enables
  automatic skin-pixel texture analysis; without it those garments go to manual review
  instead of being guessed).
- Blender 4.x with the [Sollumz](https://github.com/Sollumz/Sollumz) addon (convert /
  export / render steps only).
- CodeWalker: export the freemode component `.ydd`/`.ytd` files **as CodeWalker XML**
  (`.ydd.xml`, `.ytd.xml`) plus PNG texture dumps into `extracted/` (git-ignored).

## Never commit game assets

`extracted/` and `build/` are git-ignored, and the repo-level `.gitignore` blocks all
`ydd/ytd/yft/ymt/ycd/rpf` binaries. Only metadata (JSON manifests, reports, this
tooling) belongs in git.

## Commands

```bash
cd fivem/trophy-room/tools/mannequin_pipeline
cp config.example.json config.json          # edit paths + game build
python -m pipeline scan                     # extracted/ -> build/scan_catalog.json
python -m pipeline classify                 # -> build/classification.json, manual_review_queue.json
python -m pipeline convert                  # -> Blender jobs; runs blender --background per job
python -m pipeline export                   # -> Sollumz export to the assets resource stream/
python -m pipeline validate                 # checks exports, naming, sizes, LODs, textures
python -m pipeline build-manifest           # -> mannequin_manifest.json (stable indexes)
python -m pipeline report-coverage          # -> coverage_report.md + conversion_report.json
python -m pipeline crosscheck               # diff local scan vs reference catalog
python -m pipeline import-reference --dump …  # (maintenance) rebuild the reference
```

A **reference clothing catalog** ships in `reference/freemode_reference_catalog.json`
(aggregated from the open [DurtyFree data dumps](https://github.com/DurtyFree/gta-v-data-dumps);
metadata only — IDs and counts, no game assets). `crosscheck` uses it to verify
your extraction is complete and to detect game-build drift. Real totals per
gender are documented in `EXTRACTION_LIST.md`.

Every step is **incremental**: re-running after adding addon clothing (e.g. Romanian
Police uniforms in a new `extracted/` subfolder) only processes new/changed inputs, and
`build-manifest` allocation is **append-only** so already-placed mannequins never
re-index (see `pipeline/manifest.py`).

## Outputs

| File | Meaning |
|---|---|
| `build/scan_catalog.json` | every discovered drawable/texture, parsed identity |
| `build/classification.json` | per-drawable skin classification + rationale |
| `manual_review_queue.json` | items the pipeline refuses to guess — human decides |
| `mannequin_manifest.json` | gender/component/collection/drawable mapping (shipped to the resources) |
| `conversion_report.json` | machine-readable per-item conversion outcome |
| `coverage_report.md` | human-readable coverage %, per the acceptance criteria |

## Manual review workflow

1. Open `manual_review_queue.json`; each entry has `reason` and `evidence`.
2. Decide: set `"resolution": "skin_free" | "convert" | "incompatible"` per entry.
3. Re-run `classify` (it merges resolutions), then `convert`.

## Mannequin body build

`blender/build_mannequin_body.py` builds the original mannequin appearance assets
(faceless head, scalp cap, plastic uppr/lowr/feet twins of every base skin drawable)
from imported freemode meshes per the modeling spec in
`docs/../../docs/mannequin-modeling-spec.md`. Blender **source** files are saved under
`blender_src/` (committable, original work); exports go to the resource `stream/`
folder (git-ignored binaries, present only on the workstation and the server).
