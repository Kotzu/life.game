# Kotzu Trophy Room & Full-Body Mannequin System

A production-oriented FiveM (QBCore) trophy-room system whose flagship display type is a
**full-body, faceless, plastic mannequin** that wears dynamically selected GTA V freemode
outfits — plus an extensible display framework for weapon walls, weapon stands, cases,
rare items, and achievements.

## Repository layout

```
fivem/trophy-room/
├── README.md                     ← you are here
├── CHANGELOG.md
├── docs/                         ← ADR, guides, security review, reports, runbooks
├── tools/
│   └── mannequin_pipeline/       ← Blender/Sollumz + Python asset conversion pipeline
└── resources/
    └── [kotzu]/
        ├── kotzu_arch_proof/     ← in-game architecture proof & evidence harness
        ├── kotzu_mannequin_assets/ ← streamed mannequin body/garment assets + manifest
        └── kotzu_trophy_room/    ← the gameplay resource (client/server/bridges/web/sql)
```

## Status — read this first

All source, tooling, SQL, documentation and the in-game test harness in this tree were
developed and statically validated in a headless CI-style environment (Lua syntax
checked, Python pipeline unit-tested). **In-game acceptance evidence (screenshots,
video, Resmon numbers, architecture-proof JSON) must be produced on a machine with a
FiveM client and legally obtained GTA V assets** — this environment has neither.
The exact, step-by-step procedure is in [`docs/acceptance-runbook.md`](docs/acceptance-runbook.md).
Nothing in this repository claims in-game validation that has not happened; every
pending item is tracked in [`docs/validation-matrix.md`](docs/validation-matrix.md).

## Quick start (development sandbox)

1. Read [`docs/installation-guide.md`](docs/installation-guide.md).
2. Import `resources/[kotzu]/kotzu_trophy_room/sql/` migrations (idempotent, ordered).
3. Copy `resources/[kotzu]` into your **sandbox** server resources
   (`D:\FiveM-AI\Sandbox\kotzu_trophy_room` per project convention — never the live
   server until the acceptance suite passes).
4. `ensure kotzu_arch_proof`, join with a client, run `/archproof run`.
   This produces `arch_proof_results.json` — the evidence that locks the
   architecture decision (see the ADR).
5. Build mannequin assets with `tools/mannequin_pipeline` (requires Blender + Sollumz
   and CodeWalker-extracted freemode assets on the workstation), then
   `ensure kotzu_mannequin_assets` and `ensure kotzu_trophy_room`.

## Design pillars

- **No human skin, ever.** The client refuses to render a garment whose skin-coverage
  status is unknown; it substitutes an explicit "incompatible" state, never a
  human-skinned fallback.
- **Server-authoritative persistence.** Displays live in MySQL (oxmysql), are scoped by
  shell/property/world + routing bucket, and are recreated deterministically by clients.
- **Bridges, not couplings.** Framework (QBCore), clothing (rcore_clothing), target
  (qb-target / ox_target), inventory, and housing are all behind capability-probed
  bridge modules.
- **Atomic inventory transactions.** Weapon place/retrieve is transactional with
  idempotency keys, server-side locks, and audit logging. Duplication is treated as a
  security defect.
- **Evidence over claims.** Reports (`coverage_report.md`, `conversion_report.json`,
  `arch_proof_results.json`, performance numbers) are generated artifacts, not prose.
