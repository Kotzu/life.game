# CodeWalker Extraction List (freemode assets → `extracted/`)

Exact shopping list for the ~15-minute extraction step on the workstation.
Source: **your own GTA V installation** (CodeWalker reads the game RPFs directly).
Never use third-party "ripped model" sites: besides the licensing problem, those
conversions lose the freemode bone weights, vertex groups, LOD chain, and RAGE
shader metadata the pipeline needs to round-trip valid `.ydd` files.

## Setup (once)

1. Install [CodeWalker](https://github.com/dexyfex/CodeWalker) (GitHub releases).
2. Open **RPF Explorer**, point it at your GTA V folder, let it index.
3. In RPF Explorer options enable **XML export** for meta/model formats.

## What to export

Use RPF Explorer's **search box** (top right) — searching by filename pattern is
more reliable than memorizing RPF paths across game versions. For each pattern
below: search → select all results → right-click → **Export XML** into the
target folder. Textures: also right-click → **Export XML** (produces `.ytd.xml`)
AND **Export → PNG** (into `extracted/_png/`) so the skin-pixel classifier can run.

### 1. Base male body + clothing (target: `extracted/base_male/`)

| Search pattern | What it is |
|---|---|
| `mp_m_freemode_01^head` | head drawables (mannequin head source) |
| `mp_m_freemode_01^hair` | hair (scalp derivation source) |
| `mp_m_freemode_01^uppr` | torso/arm skin variants (plastic twins) |
| `mp_m_freemode_01^lowr` | legs (incl. designated bare-body drawable) |
| `mp_m_freemode_01^hand` | hands |
| `mp_m_freemode_01^feet` | feet/shoes |
| `mp_m_freemode_01^teef` | teeth (exported hidden) |
| `mp_m_freemode_01^jbib` | tops |
| `mp_m_freemode_01^accs` | undershirts/accessories |
| `mp_m_freemode_01^task` | vests/tasks |
| `mp_m_freemode_01^decl` | decals |
| `mp_m_freemode_01^berd` | masks |
| `mp_m_freemode_01^p_` | props (hats/glasses/etc.) |

The main hits live in `x64v.rpf\models\cdimages\streamedpeds_players.rpf\`
(and `streamedpedprops.rpf` for props) — but trust the search, not the path.

### 2. Base female (target: `extracted/base_female/`)

Same 13 patterns with `mp_f_freemode_01^…`.

### 3. DLC clothing (optional now, per-pack later)

Patterns `mp_m_freemode_01_<dlc>^…` / `mp_f_freemode_01_<dlc>^…` (e.g.
`mp_m_freemode_01_mp_heist3^`). Start WITHOUT these: get the base game to 100%
coverage first, then add DLC packs incrementally (`scan` only processes new
files, and manifest indexes never shift).

### 4. Texture PNG dumps (target: `extracted/_png/`)

For every `.ytd` exported above, also export its textures as PNG. CodeWalker:
open the `.ytd` → select all textures → **Save All** as PNG. Without PNGs the
classifier can't run skin-pixel analysis and sends those garments to manual
review instead (safe, but slower for you).

## Sanity check before running the pipeline

```
python -m pipeline scan
```
Expect roughly: male base ≈ 200–400 drawables, female similar (varies by build).
`skipped` entries should be only non-freemode strays. Then continue with
`classify` per the README.

## Reminder

`extracted/` and `_png/` are git-ignored — these files never leave your machine
except when deployed to your own server's `stream/` after conversion.
