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
