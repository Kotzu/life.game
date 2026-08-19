# ADR-001 — Mannequin Technical Architecture

Status: **SELECTED: Candidate B + C — provisional pending in-game proof run**
(finalize by executing `kotzu_arch_proof` and attaching `arch_proof_results.json` +
screenshots; the decision auto-finalizes if tests `B1–B6`, `C1` pass and `A2` fails as
predicted. If `A2` *passes*, re-evaluate per the decision rule below.)

## 1. Problem

We need male/female full-body mannequins that are genuinely faceless plastic on every
exposed surface, yet wear **dynamically selected** GTA V freemode outfits (default
clothing now, addon clothing later), on the standard freemode skeleton, statically
posed and persistent.

## 2. Candidates

### Candidate A — dedicated addon mannequin ped
A custom streamed ped (freemode skeleton) that would somehow reuse the original
`mp_m_freemode_01` / `mp_f_freemode_01` clothing collections.

### Candidate B — original freemode ped + mannequin component collection
Use the real freemode models. Ship an **addon clothing pack** (a DLC-style collection,
working name `mannequin`) that adds mannequin *body* drawables for the skin-bearing
components, then dress the ped with original garments for everything that shows no skin.

### Candidate C — converted skin-bearing garments
For garments whose drawable embeds human-skin geometry/material (open shirts, shorts,
skirts, sandals…), generate a converted copy in the `mannequin` collection where only
the skin surfaces are re-materialed to mannequin plastic; garment textures untouched.

## 3. Engine constraints (documented behavior, verified by proof tests)

| # | Constraint | Confidence / source | Proof test |
|---|---|---|---|
| E1 | Component variations (drawables/textures) are declared **per ped model** in that model's variation metadata (`mp_m_freemode_01.ymt` + `shop_ped_apparel` DLC packs targeting that exact model name). `SetPedComponentVariation` resolves indexes only against the entity's own model data. | High — this is how every addon-clothing pack works: they must name files `mp_m_freemode_01_<dlc>^…` to attach to the freemode model. There is no native that mounts another model's clothing library onto a ped. | A2 |
| E2 | Therefore an addon ped (Candidate A) gets **none** of the freemode clothing library unless the entire library's variation metadata is duplicated against the new model name — which also breaks with every game build update and bloats streaming memory. | High | A1/A2 |
| E3 | FiveM exposes **collection natives** (`SetPedCollectionComponentVariation`, `GetPedDrawableVariationCollectionName`, `GetPedDrawableVariationCollectionLocalIndex`, `GetNumberOfPedCollectionDrawableVariations`, `SetPedCollectionPropIndex`, `GetPedCollectionsCount`, `GetPedCollectionName`) that address drawables by `(collectionName, localIndex)` instead of fragile global indexes. Addon packs (including rcore-managed ones) appear as named collections on the freemode peds. | High — documented FiveM natives (build 2189+) | B1, B2 |
| E4 | Freemode "skin" lives in specific components: head `0`, torso/arms `3` (`uppr`), legs `4` (`lowr`), feet `6`, plus skin embedded inside some garment drawables of `11` (`jbib`), `8` (`accs`), `4`, `6`. Replacing components 0/3/4/6 with addon drawables replaces all *base* skin. | High — standard freemode component layout | B3, B4 |
| E5 | Freemode faces are head-blend driven; a custom head drawable in component 0 plus `SetPedHeadBlendData(ped,0,0,0,0,0,0,0,0,0,false)` and all `SetPedHeadOverlay(i,255,…)` yields a stable non-human head with no overlays. Hair is component 2 → set to drawable with "no hair" or a mannequin scalp drawable. | High | B5 |
| E6 | Garments that embed skin geometry inside the garment drawable can only be fixed at the **asset** level (Candidate C); no runtime native recolors sub-materials of a drawable. | High | C1 |
| E7 | A **local, non-networked** ped (`CreatePed(..., false, false)`) is deterministic per client, costs no network sync, cannot be interfered with by other clients, and is the standard technique for client-side "display" NPCs driven by shared server data. Networked peds add migration/ownership churn for zero benefit for a frozen statue. | High | B6 (stability), MP tests in acceptance suite |

## 4. Decision rule (from the master brief)

Choose A **only if** original freemode clothing compatibility is proven broadly without
duplicating every garment. E1/E2 predict this is impossible; test A2 exists to prove it
honestly rather than assume it. Otherwise choose **B + C**. Reject anything leaving
human skin visible or blocking dynamic outfits.

## 5. Selected architecture — B + C

1. **Model**: original `mp_m_freemode_01` / `mp_f_freemode_01`, spawned as *local*
   frozen/invincible peds from server registry data (E7).
2. **Mannequin body**: addon clothing collection `mannequin` streamed by
   `kotzu_mannequin_assets`, containing faceless head (comp 0), scalp (comp 2), plastic
   uppr (comp 3), lowr (comp 4), feet (comp 6) drawables per gender, built by
   `tools/mannequin_pipeline` from original freemode meshes (geometry preserved,
   materials replaced with mannequin plastic; face simplified per modeling spec).
3. **Outfits**: captured from players via the clothing bridge, normalized to
   `(componentId, collectionName, localDrawable, texture)` tuples (E3). At render time
   each garment is looked up in `mannequin_manifest.json`:
   - `skin_free` → apply original garment;
   - `converted` → apply the converted twin from the `mannequin` collection (C);
   - `unknown`/`incompatible` → **refuse**: the mannequin renders in base plastic with
     an explicit "outfit incompatible" state surfaced in UI/logs. Never human skin.
4. **Props** (hats/glasses/masks/etc.): applied via collection prop natives; props never
   contain body skin and pass through unless the manifest flags an exception.

## 6. Rejected alternatives

- **Candidate A** — rejected per E1/E2: requires duplicating the entire clothing
  library per game build; unmaintainable, memory-hostile, and still needs C for
  skin-embedded garments. Re-open only if proof test A2 unexpectedly shows a supported
  cross-model collection mount.
- **Human ped + white mask / gloves-only / shader tricks / single-outfit baked addon
  ped / static prop** — all explicitly forbidden by the brief and all fail either the
  "no skin anywhere" or the "dynamic outfits" requirement.
- **Networked display peds** — rejected by default per E7; the acceptance suite's
  two-client tests exist to catch any counter-evidence (if local peds ever desync from
  registry state, the spawner interface allows a networked strategy behind the same
  abstraction).

## 7. Proof tests (executable: `kotzu_arch_proof`, `/archproof run`)

| ID | What it proves | Pass condition |
|---|---|---|
| A1 | Whether a custom addon ped model is even present to test | model loads (else SKIPPED — A rejected on E1/E2 grounds + doc evidence) |
| A2 | Whether an addon ped can address freemode collections | `GetNumberOfPedCollectionDrawableVariations` on freemode collection names returns >0 on the addon ped (**expected: 0/fail**) |
| B1 | Collection natives enumerate on freemode ped | `GetPedCollectionsCount` > 0; names listed |
| B2 | Collection-addressed dressing round-trips | set via `SetPedCollectionComponentVariation`, read back same `(collection, localIndex)` |
| B3 | Components 0/2/3/4/6 accept addon drawables | after `kotzu_mannequin_assets` streams, `mannequin` collection variation count > 0 per component |
| B4 | No base skin visible with mannequin components applied | operator screenshot checkpoint |
| B5 | Neutral head blend + overlay clear is stable | overlays read back 255; screenshot checkpoint |
| B6 | Local frozen ped stability | position/heading unchanged after 60 s, damage event, and re-stream |
| C1 | Converted-garment collection lookups work | converted drawable resolves and applies |
| N1 | Local vs networked ped comparison | timings + behavior recorded to JSON |

Results are written server-side to `kotzu_arch_proof/arch_proof_results.json` together
with game build, client version, and timestamps. Screenshot checkpoints are prompted
on-screen during the run (see acceptance runbook).

## 8. Known constraints & risks carried into implementation

- Converted-garment coverage is finite and enumerated; `coverage_report.md` is the only
  legitimate source of "supported" claims (brief §6).
- `mannequin` collection local indexes must stay **stable across pipeline re-runs**
  (append-only manifest allocation; enforced by `build-manifest`).
- Head blend on non-player peds requires the ped to be of freemode model and alive;
  spawner sequences blend → components → props → freeze, and re-applies on re-stream.
- Game build differences change default-clothing enumeration; the catalog stores the
  build it was scanned on.
