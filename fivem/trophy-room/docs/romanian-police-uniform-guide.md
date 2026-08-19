# Romanian Police Uniform Onboarding Guide

Specific walkthrough for the planned Romanian Police uniform packs, building on
`custom-clothing-integration-guide.md`.

## 1. Source the pack correctly

- Use uniforms rigged for `mp_m_freemode_01` / `mp_f_freemode_01` (EUP-style packs).
  Ped-model uniforms (full custom peds) are NOT compatible with the mannequin system —
  they bypass the component system entirely.
- Verify licensing allows use on your server. Never commit the assets to git.

## 2. Expected components in a police pack

| Piece | Component | Typical skin risk |
|---|---|---|
| Tunic/blouson (cămașă/geacă) | 11 jbib | low (long sleeve) / medium (short-sleeve summer shirt: forearms) |
| Under-shirt / kevlar | 8 accs | low |
| Trousers | 4 lowr | low (full length) |
| Boots | 6 feet | low |
| Duty belt | 8 accs or 9 task | none |
| Tactical vest ("POLIȚIA") | 9 task | none |
| Epaulettes/badges (decals) | 10 decl | none |
| Cap / beret | prop 0 | none |
| Arm patches | often baked into jbib textures | none |

Short-sleeve summer shirts are the main conversion candidates: the forearm skin is
usually part of the **uppr** body drawable, which the mannequin body set already
replaces — so most Romanian Police garments should classify `skin_free` automatically.
Only shirts with skin baked into the jbib mesh itself need converted twins.

## 3. Run the pipeline

Exactly as in the integration guide; put exports under
`extracted/romanian_police/`. After `classify`, expect nearly everything
`skin_free`; review any ambiguous texture hits (badge golds/beiges can trip the skin
detector — that's what the review queue is for; resolve as `skin_free`).

## 4. In-game validation checklist

1. `/kmq:reload_manifest`.
2. Dress a character in each full uniform variant (summer, winter, tactical, traffic).
3. `/kmq:spawn_dressed` for each; verify: shoulder patches readable, vest text intact,
   belt props present, no skin at collar/wrists/ankles, cap prop seated correctly.
4. Screenshot each variant into `captures/romanian_police/` and add rows to
   `clothing-compatibility-report.md`.

## 5. Display-room presentation tips

- Pose `attention` (military attention) suits formal uniforms; `at_ease` for tactical.
- Use the `round` platform and a label like "Uniformă de patrulare — 2026".
- For a ceremony wall: several mannequins at 0.5 m snap increments face the room
  center (Tab cycles snap during placement).
