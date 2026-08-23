# Design Reference — Trophy Room / Mannequin System

`concept-target.png` is the visual target supplied by the project owner. Per the
brief §17 it is a **design north star, not an in-game screenshot** — nothing in
this repo claims the concept image is a captured result. In-game visuals come
only from the acceptance runbook (T1/T2/T20).

## Concept → implementation map

| Concept element | Status | Where |
|---|---|---|
| Faceless off-white plastic mannequins, male + female | built (assets pending extraction) | `client/mannequin.lua`, pipeline |
| Premium dark UI with gold accent | built | `web/style.css` (tokens `--accent #c9a860`) |
| Mannequin menu: Place / Edit / Change Outfit / Change Pose / Change Gender / Remove | built | `client/interaction.lua`, `web/app.js` |
| SELECT OUTFIT panel — list, selected highlight, "N/total", saved subtitle, SELECT/CANCEL | built | `web/app.js` outfit list, `bridge/clothing/illenium.lua` savedList |
| Pose selection list (Default Stand, Arms Crossed, Hands Behind Back, Hands On Belt, Military…, Relaxed, T-Pose) | built, anim-verified | `shared/config.lua` Poses |
| Place mannequin: ghost preview + key hints (Cancel / Place / Rotate / Delete) | built | `client/placement.lua` |
| Persistent & visible for everyone | built | server registry + bucket broadcast |
| qb-target interactions (Manage / Take Outfit / Wear Outfit / Rotate / Remove) | built (+ox_target) | `bridge/target/*`, `client/interaction.lua` |
| Lit display plinth under each mannequin | built (platform) | `Config.Platforms` (`round`, `plinth`) |

## Palette (matched to the concept)

- Background near-black warm: `#100f0e` / `#1c1a18`
- Gold accent: `#c9a860`, hover `#e6cf96`
- Text `#e8e3da`, muted `#96908a`
- Selected row: gold border + `#262119` fill (as the highlighted "Black Suit" row)

## Notes on fidelity

- "Looking Left / Looking Right" from the concept are achieved via the mannequin's
  heading in placement/rotate (R), not separate anim clips — GTA has no reliable
  static "look" idle without held props. All other concept poses map to verified
  base-game clips/scenarios.
- Outfit "saved date" in the concept: illenium's `player_outfits` table has no
  timestamp column, so the panel shows the outfit name + source model as the
  subtitle instead of inventing a date.
