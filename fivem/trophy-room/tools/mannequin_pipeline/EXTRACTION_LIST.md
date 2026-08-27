# CodeWalker Extraction List (freemode assets → `extracted/`)

Exact shopping list for the ~15-minute extraction step on the workstation.
Source: **your own GTA V installation** (CodeWalker reads the game RPFs directly).
Never use third-party "ripped model" sites: besides the licensing problem, those
conversions lose the freemode bone weights, vertex groups, LOD chain, and RAGE
shader metadata the pipeline needs to round-trip valid `.ydd` files.

## Setup (once)

1. Install CodeWalker — official channels only: the
   [GTA5-Mods page](https://www.gta5-mods.com/tools/codewalker-gtav-interactive-3d-map)
   by dexyfex, or the CodeWalker Discord `#releases` channel. (The GitHub repo
   is source-only, no binaries.)
2. Open **RPF Explorer**, point it at your GTA V folder, let it index.
3. In RPF Explorer options enable **XML export** for meta/model formats.

## How the names actually work (read this first)

The in-game streaming name `mp_m_freemode_01^jbib_000_u` is **virtual**:
`folder^file`. The `^` character never appears on disk. Inside the RPFs there
is a **folder** per ped/collection, holding plainly-named files:

```
mp_m_freemode_01/            jbib_000_u.ydd, uppr_000_u.ydd, head_000_r.ydd, ...
mp_m_freemode_01_p/          p_head_000.ydd, ...                 (base props)
mp_m_freemode_01_mp_heist3/  jbib_000_u.ydd, ...                 (one DLC pack)
```

So searching for `mp_m_freemode_01^head` finds nothing — search for the
**folder names** instead (searching `mp_m_freemode_01` lists them all: the two
base folders plus every DLC collection folder).

**The scanner derives each file's identity from its parent folder name**, so
when you export, always export INTO a local folder with the SAME name as the
RPF folder it came from. Layout the pipeline expects:

```
extracted/
  base_male/
    mp_m_freemode_01/        <- all files from that RPF folder
    mp_m_freemode_01_p/
  base_female/
    mp_f_freemode_01/
    mp_f_freemode_01_p/
  _png/
    mp_m_freemode_01/        <- PNG texture dumps, per source folder
    ...
```

## What to export

Per folder: open it in RPF Explorer (search for its name, or browse — base
components live under `x64v.rpf\models\cdimages\streamedpeds_mp.rpf\`, props
under `streamedpedprops.rpf\`, but trust the search, not the path), then
**select all files inside → right-click → Export XML** into the matching local
folder above.

### 1. Base male (target: `extracted/base_male/`)

| RPF folder | Contents |
|---|---|
| `mp_m_freemode_01` | all components: head/hair/uppr/lowr/hand/feet/teef/jbib/accs/task/decl/berd + their `.ytd` textures |
| `mp_m_freemode_01_p` | all props (hats/glasses/etc.) |

### 2. Base female (target: `extracted/base_female/`)

Same two folders with `mp_f_freemode_01` / `mp_f_freemode_01_p`.

### 3. DLC clothing (optional now, per-pack later)

Folders `mp_m_freemode_01_<dlc>` / `mp_m_freemode_01_p_<dlc>` (e.g.
`mp_m_freemode_01_mp_heist3`) and the `mp_f_…` twins — searching
`mp_m_freemode_01` shows the full list (hundreds of folders across the DLC
rpfs). Start WITHOUT these: get the base game to 100% coverage first, then add
DLC packs incrementally, each into its own same-named folder (`scan` only
processes new files, and manifest indexes never shift).

### 4. Textures for the skin-pixel classifier

**Usually nothing to do**: CodeWalker's Export XML also writes each `.ytd`'s
textures as `.dds` next to the exported `.ytd.xml`, and the classifier reads
those directly (Pillow decodes DDS). Only if your CodeWalker build does NOT
emit the `.dds` files, fall back to manual PNG dumps: open each `.ytd` →
select all textures → **Save All** as PNG into
`extracted/_png/<rpf-folder-name>/` (plain texture names repeat across DLC
packs, the subfolder keeps them apart). Without either, affected garments go
to manual review instead (safe, but slower for you).

## Sanity check before running the pipeline

```
python -m pipeline scan
python -m pipeline crosscheck   # diffs your extraction against the reference catalog
```

Real expected counts (from the committed reference catalog, built from the open
DurtyFree metadata dump — `reference/freemode_reference_catalog.json`):

| Scope | Male | Female |
|---|---|---|
| Base game only | 192 component drawables + 39 props | 183 + 38 |
| Full (base + 43 MP DLC collections) | 1,953 component drawables + 336 props | 2,063 + 314 |
| …of which garments (need skin classification) | 1,340 | 1,442 |
| …of which body-skin (mannequin twins) | 613 | 621 |

`crosscheck` tells you exactly which drawables your extraction is missing and
which local ones the reference doesn't know (addon packs / build drift) — no
guessing about whether the export was complete.

## Reminder

`extracted/` and `_png/` are git-ignored — these files never leave your machine
except when deployed to your own server's `stream/` after conversion. The JSON
reports under `build/` (scan/crosscheck/classification) are metadata-only and
safe to commit for remote review.
