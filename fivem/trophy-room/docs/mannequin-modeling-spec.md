# Mannequin Modeling Specification (Blender / Sollumz)

Applies to the mannequin body set for both genders. Enforced by
`blender/build_mannequin_body.py` defaults plus a manual art pass on the saved
`blender_src/*.blend` sources; verified by contact sheets and in-game checkpoints
B4/B5 of the acceptance suite.

## Head (component 0)
- Faceless: eye sockets, mouth seam, and nostril cavities closed (automated cavity
  smoothing, then manual cleanup). **No eye geometry, no mouth cavity.**
- Silhouette retained: simplified but recognizable nose bridge and brow so the head
  reads as "retail mannequin", not "egg".
- Teeth (comp 7) exported empty/hidden — no mouth means no teeth.
- No head blend overlays are relied upon; the client also clears overlays defensively.

## Scalp (component 2)
- Continuous cranium cap derived from the head mesh; replaces hair entirely.
- Must meet the head with no visible seam under direct light.

## Body (components 3 uppr / 4 lowr / 6 feet, hands comp 5)
- Geometry: original freemode meshes (proportions therefore match all clothing cuts).
- One plastic twin per original base skin drawable variant so every garment cut
  (sleeveless, rolled sleeves, shorts, skirts, sandals) has a matching body piece.
- Skeleton, vertex groups, weights, UVs, and custom normals untouched — this is a
  material/detail conversion, never a re-rig.
- No destructive skeleton changes; the freemode skeleton is the skeleton.

## Material
- Single shared material: warm off-white `RGB(231, 228, 222)`, semi-matte
  (specular intensity ≈ 0.18, tight falloff), exported as a game ped shader
  (`ped_default.sps`) — **never** a Blender-only BSDF.
- No subsurface, no skin detail maps, no tattoos/overlay layers.
- Must read as plastic under: dark trophy-room spot lighting AND flat daylight
  (contact sheets render both rigs; in-game checkpoints repeat the check).

## Seams
- Head/neck, wrist, and ankle junctions must be visually continuous (shared border
  vertex positions + matching normals along the seam rings).

## Budgets
- Head+scalp ≤ 25k tris combined at LOD0; body pieces stay within the source mesh
  budget (conversion adds no geometry).
- LODs: preserve the source LOD chain; the plastic material is applied to every LOD.
- Textures: the shared 64×64 flat plastic texture; no per-piece diffuse maps.

## Evidence
- Blender contact sheets (`render_contactsheet.py`) = pipeline QA only.
- FiveM screenshots at checkpoints B4/B5 and the §6 clothing matrix = acceptance.
