# Changelog

## [1.0.0-dev] — 2026-08-19

Initial full implementation (headless development environment; in-game acceptance
pending — see `docs/validation-matrix.md`).

### Added
- **ADR-001** with Candidate A/B/C analysis and executable proof harness
  (`kotzu_arch_proof`, `/archproof run` → `arch_proof_results.json`).
- **Asset pipeline** (`tools/mannequin_pipeline`): scan / classify / convert / export /
  validate / build-manifest / report-coverage; optional skin-pixel texture analysis;
  never-guess manual review queue; append-only stable manifest allocation; Blender/
  Sollumz headless jobs (garment conversion, mannequin body build with facial-cavity
  closing + scalp derivation, dual-light contact sheets). 16 unit tests.
- **kotzu_mannequin_assets**: `mannequin` collection registration for both freemode
  models; seed manifest v0 with explicit `MANIFEST_NOT_BUILT` semantics.
- **kotzu_trophy_room**:
  - shared schemas (outfit v2 normalized to collection+local indexes, v1 migration),
    RPC, locales, config;
  - bridges: QBCore/standalone framework, native+rcore clothing (capability probing),
    qb-target/ox_target/fallback, qb/ox/refusing-fallback inventory, generic housing
    contract with shell-relative transforms and test shells;
  - server: idempotent SQL migrations, cached repository, capability-based
    permissions, strict validation (size/schema/whitelists/distance/bucket/manifest
    compatibility), rate limiting, atomic idempotency-keyed weapon transactions with
    startup recovery + audit log;
  - client: 1 Hz batched streaming with hysteresis and uid-keyed dedupe, manifest-
    driven mannequin dresser (plan-then-apply, zero-skin invariant), pose system,
    renderer registry (mannequin/weapon wall/stand/case/rare item/achievement),
    ghost-preview placement, crash-safe visitor try-on, capability-gated target
    interactions, dependency-free dark NUI;
  - test harness: `/kmq:*` suite incl. §6 outfit matrix, pose stability, streaming/
    reconnect simulation, routing-bucket shells, DB validation, weapon-tx rollback.
- **Documentation**: environment audit, modeling spec, acceptance runbook, validation
  matrix, security review, performance report (procedure + unfilled tables — no
  invented numbers), clothing compatibility contract, custom clothing + Romanian
  Police guides, installation/admin/player guides.

### Fixed (during development)
- Per-gender coverage counters in `report-coverage` were seeded from running global
  totals (caught by the CLI smoke test).
- Weapon-place unique-id now derives from the server-found inventory item; client
  metadata is only a narrowing filter.

### Known limitations
- Mannequin binary assets are not in git (by design); build via pipeline.
- rcore_clothing saved-outfit apply depends on the installed build's exports
  (capability-probed, surfaced via `/kmq:probe_clothing`).
- All in-game acceptance evidence pending (no FiveM client in the dev environment).

## [1.0.1-dev] — 2026-08-19

### Fixed (self code-review, 4 findings, all addressed)
- Rate limiter used `os.clock()` (CPU time) instead of wall-clock; now
  `GetGameTimer()` — the per-minute limits are real minutes.
- Bare-mannequin skin leak: lowr(4)/feet(6) base drawables are now designated
  body pieces produced by the pipeline (`body_base` config), the client refuses
  spawn if they're missing, and `pipeline validate` checks the exact component
  set the runtime requires (0/2/3/4/5/6) — producer, validator and consumer now
  agree.
- `displays:delete` keyed its weapon guard on item presence, permanently
  blocking removal of rare_item/achievement displays; now keys on display type.

### Added
- `tools/setup-sandbox.ps1`: one-click Windows sandbox installer with live-server
  safety rail, prerequisite scan, mirrored copy, and server.cfg guidance.

## [1.0.2-dev] — 2026-08-23

### Added — headless integration verification (no FiveM client needed)
- `tools/fxsim/`: FXServer-environment simulator (natives/events/scheduler/
  oxmysql shims) running the REAL server scripts against REAL MariaDB —
  **32/32 scenario checks pass** (S1–S11: boot/migrations, placement,
  permissions, validation, rate limits, full weapon transaction with
  idempotent replay + zero duplication + stranded-lock recovery, DB
  consistency). Evidence: `tools/fxsim/last_run.txt`,
  `docs/headless-verification-report.md`.
- SQL semantics proven directly on MariaDB 10.11 (INSERT IGNORE gate,
  soft-delete-as-lock, idempotent migrations).

### Fixed — Sollumz API verification against real source + headless Blender
- Confirmed: `sollumz.import_assets(directory, files)`,
  `sollumz.export_assets`, `create_shader('ped_default.sps')` (szio
  ShaderManager). Gap fixed: install-dependent Sollumz module path
  (`Sollumz` addon vs `bl_ext.<repo>.sollumz[_dev]` extension) now resolved
  dynamically; export now passes `direct_export=True` for headless runs.

## [1.0.3-dev] — 2026-08-23

### Added — reference clothing catalog (from open metadata, no game assets)
- `reference/freemode_reference_catalog.json`: aggregated from the open
  DurtyFree `gta-v-data-dumps` (pedComponentVariations_free.json, commit
  b65684e) — every freemode drawable/texture count per collection, both
  genders. Real §6 denominators now known: male 1,340 garment + 613 body +
  336 prop drawables; female 1,442 + 621 + 314 (base + 43 DLC collections).
- New pipeline commands: `import-reference` (rebuild the catalog from a dump)
  and `crosscheck` (diff a local extraction against the reference —
  missing/unknown/texture-mismatch, exit 1 on gaps).
- EXTRACTION_LIST + compatibility report updated with the real counts.
- +2 test modules (19 pytest cases total, all passing).

## [1.1.0-dev] — 2026-08-23

### Added — first-class Qbox framework support (verified against real sources)
- `bridge/framework/qbox.lua`: qbx_core identity (PlayerData.citizenid,
  job.grade.level), ACE/HasPermission admin checks, qbx Notify server-side +
  ox_lib notify client-side. Verified against Qbox-project/qbx_core source;
  outranks the qb-core bridge when both are present.
- `bridge/clothing/illenium.lua`: illenium-appearance support — saved outfits
  read SERVER-side from its `player_outfits` table (feature-detected), payloads
  normalized from global drawable indexes to (collection, local) via the
  global->collection lookup natives (`NormalizeIllenium`).
- Saved-outfit RPCs (`outfit:savedList` / `outfit:savedGet`) with per-citizen
  ownership enforced in SQL; wizard "Saved outfit…" path now actually applies
  the selected outfit.
- ox_inventory/ox_target bridges re-verified against CommunityOx sources
  (Search/AddItem/RemoveItem export names confirmed).
- fxsim: external-exports faking; whole suite now runs on the Qbox identity
  path + 5 new S12 checks — **37/37 passing** on real MariaDB.

## [1.1.1-dev] — 2026-08-23

### Fixed — pose set verified against the game's real animation data
- Replaced pose entries whose anim clips don't exist in-game (verified against
  the DurtyFree animDictsCompact dump, 20,179 dicts): `neutral` now uses the
  real per-gender corona team-idle clips; `attention`/`at_ease`/`guard`/
  `inspect` use verified scenarios; `hands_back`/`arms_crossed`/`relaxed` use
  verified dict+clip pairs. Added `guard` and `inspect` poses.
- poses.lua: per-gender dict resolution (genderDict) with a shared-dict then
  scenario fallback cascade, so no pose can silently leave a ped in A-pose.

### Added
- Full Romanian (`ro`) locale pack for notifications/target labels.
- `Config.DemoLayout` + `/kmq:demo_layout`: ready-made trophy-room arrangement
  (3 mannequins + 2 weapon displays, shell-relative) for acceptance T8/previews.

## [1.1.2-dev] — 2026-08-23

### Added — alignment to the design concept (docs/design/concept-target.png)
- Concept image preserved as the design north star + concept→implementation
  map (`docs/design/README.md`); explicitly NOT an in-game screenshot.
- Pose list relabeled/reordered to match the concept (Default Stand, Arms
  Crossed, Hands Behind Back, Hands On Belt, Military Attention/At Ease,
  Security Guard, Inspecting, Relaxed, T-Pose); added anim-verified
  `hands_on_belt` (cop idle base).
- NUI "SELECT OUTFIT" panel rebuilt to match the concept: list with selected-
  row highlight, live "N / total" counter, and a footer showing the outfit
  name + source model (illenium has no saved-date column, so no invented date).
- Concept palette documented and confirmed against style.css tokens.

## [1.1.3-dev] — 2026-08-23

### Fixed — second self code-review (8 findings, all addressed)
- Saved-outfit flow never silently substitutes: missing bridge support, no
  selection, or a failed fetch all abort with a visible error; the UI blocks
  "Start placement" (with visual feedback) until a saved outfit is picked.
- `player_outfits` feature detection no longer caches a negative probe —
  transient DB errors or late illenium startup can't disable saved outfits
  until restart.
- run-extraction.ps1: Pillow probe survives PS 5.1 + EAP=Stop; classify exit
  code now checked (no more false "extraction complete").
- Sollumz resolver re-gained the `shared/shader_materials` layout fallback.
- `/kmq:demo_layout` refuses to run outside a room (its transforms are
  room-relative; would have persisted displays near the map origin).
- New `Bridge.Find(kind, name)` helper replaces three hand-rolled registry
  scans (rcore ×2, illenium ×1).

### Added — fully localized NUI
- All web UI strings now come from the Lua locale packs (`ui` tables, en + ro,
  per-key English fallback) delivered on every screen open; `Config.Locale =
  'ro'` localizes the entire interface including the SELECT OUTFIT panel.

## [1.2.0-dev] — 2026-08-23

### Added — trophy case shapes + showcase auto-rotate
- Three case styles using base-game props (names verified against the object
  list): `ch_prop_ch_case_sm_01x` (cube), `ch_prop_ch_case_01a` (vertical
  museum case), `w_am_case` (Ammu-Nation counter) — selectable in the wizard
  ("Case shape"), persisted per display (`case_style` column).
- Per-display settings (`settings` column, migration 004, idempotent
  ADD COLUMN IF NOT EXISTS): `rotate = { enabled, speed }` with server-side
  bounds validation (3–90 °/s). Owner menu "Auto-rotate" opens a NUI screen
  with toggle + speed slider (en+ro).
- `client/rotator.lua`: showcase spin for case/stand items; the per-frame
  thread exists ONLY while ≥1 rotating display is streamed in, and exits
  completely otherwise (perf contract documented in-file).
- fxsim S13 (5 checks): case place with style+settings, DB persistence,
  settings update, out-of-range speed rejected, unknown style rejected —
  suite now **43/43** on real MariaDB.
- 3D demo updated: three case shapes with rotating items and a live
  toggle + speed slider on the selection card.

## [1.2.1-dev] — 2026-08-23

### Security — weapon anti-dupe hardening + clothing dupe audit
- Closed the classic FiveM race (concurrent place of the same weapon
  interleaving between FindItem and RemoveItem across the cooperative-yield
  boundary): added a **synchronous per-citizen critical-section lock** in
  transactions.lua acquired before the first yield.
- Added **serial-uniqueness guard** (`Repo.SerialInUse`) checked inside the
  critical section: a serial already on a live display refuses the second place
  with a new `DUPLICATE` error and a `weapon_dupe_blocked` audit row; retrieving
  frees the serial for re-placement.
- Audited clothing: grep-verified the ONLY inventory mutations are the weapon
  transaction; outfit capture/try-on/saved-outfit are cosmetic/read-only — no
  economy dupe. Documented that rare-item displays are decorative and must use
  the weapon transaction if ever tied to real inventory.
- `docs/anti-dupe-analysis.md`: enumerated matrix W1–W12 + clothing, each mapped
  to its defense and test; linked from the security review.
- fxsim S14 (serial uniqueness, re-place after retrieve, lock present) + S15
  (outfit RPCs never touch inventory) — **51/51 checks pass** on real MariaDB.

## [1.2.2-dev] — 2026-08-23

### Security — third code-review on the anti-dupe code (4 findings, all fixed)
- **Lock lockout (HIGH)**: an error inside the critical section skipped
  `release()`, locking that citizen out of weapon ops until a process restart.
  Added `withLock` (pcall-wrapped, always releases) + `playerDropped` cleanup.
- **Serial squatting (HIGH)**: a free `rare_item`/`achievement` display carrying
  a crafted `item.metadata.serial` could mark a victim's serial "in use" and
  lock the real owner out (serials are broadcast to nearby clients, so they are
  discoverable). Now `SerialInUse` scans only `weapon_*` displays AND
  serial-like fields are stripped from non-weapon placements.
- **Cross-citizen serial race (MEDIUM)**: the serial check sat inside the
  per-citizen section only, so two different citizens could both pass it. Added
  a synchronous `claimSerial` reservation (no yield between check and claim),
  released on every failure path.
- **Vacuous S15 test (LOW)**: the clothing-dupe proof short-circuited before
  reaching outfit logic. Rewritten against a live mannequin display + populated
  `player_outfits` row, asserting byte-identical inventory.
- Docs corrected: W2 rewritten, W13/W14 added, rate-limit buckets fixed.
- fxsim: S15 rewritten, S16 (squatting) + S17 (lock release on error) added —
  **62/62 checks pass** on real MariaDB.

### Changed — demo mannequins rebuilt on freemode proportions
- `docs/design/room-demo-scene.js`: mannequins now follow the mp_m/f_freemode_01
  skeleton metrics (1.87 m / 1.75 m, 7.5-head figure, clavicle/elbow/wrist/knee
  heights, male 1.45 shoulder-to-hip vs female hourglass), with tapered limbs,
  articulated elbows, mannequin hands (palm + fused fingers + thumb), jaw and
  nose-ridge silhouette, still faceless. Scene now shows 3 male + 1 female
  mannequin; the info card names the source model.
- Browser test updated and re-run: **16/16 pass** in headless Chromium.
