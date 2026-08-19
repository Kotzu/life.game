# Environment Audit

Date: 2026-08-19 · Auditor: automated (Claude Code remote session)

## Where this code was developed

| Item | Value |
|---|---|
| Development host | Remote Linux container (headless, ephemeral) |
| Repository | `kotzu/life.game`, branch `claude/fivem-trophy-mannequin-d5lwja` |
| Python | 3.11.15 (pipeline developed & unit-tested here) |
| Node | 22.x (NUI assets are dependency-free vanilla JS; Node used only for optional lint) |
| Lua toolchain | `luaparser` (syntax validation of every shipped `.lua`) |
| Blender / Sollumz | **NOT available** in this container |
| FiveM client / server | **NOT available** in this container |
| GTA V game assets | **NOT available** (and must never be committed — see `.gitignore` rules) |

## Target environment (declared by project owner)

| Item | Value |
|---|---|
| Framework | QBCore |
| Clothing system | rcore_clothing |
| Database | oxmysql (MySQL/MariaDB) |
| Target resource | qb-target and/or ox_target — detected at runtime by the target bridge |
| Dev workspace (Windows) | `D:\FiveM-AI\Sandbox\kotzu_trophy_room` |
| Live server (DO NOT TOUCH until acceptance passes) | `E:\FiveMserver\server` |
| Freemode models | `mp_m_freemode_01`, `mp_f_freemode_01` |
| Clothing scope | default GTA V clothing now; addon (Romanian Police) later |

## Consequences for the workflow

1. **Everything executable headlessly was executed headlessly**: Python pipeline unit
   tests, Lua syntax validation across all resources, SQL reviewed for idempotency.
2. **Everything requiring a game client is packaged as an executable harness**, not as
   claims: `kotzu_arch_proof` (architecture proof + JSON evidence writer),
   `kotzu_trophy_room/tests` (acceptance commands), and `docs/acceptance-runbook.md`
   (exact operator procedure, including screenshot/video capture points).
3. **The architecture decision record** distinguishes *documented engine constraints*
   (cited, high confidence) from *facts the proof harness must confirm in-game*
   (explicitly listed, each mapped to a test ID). The decision is recorded as
   **provisional-pending-proof-run** and the harness writes the evidence that finalizes
   it.
4. **rcore_clothing is a paid resource not present in this repo**, so its bridge uses
   runtime capability probing (`pcall` of candidate exports, logged) plus a
   native-based capture path that works regardless of rcore version. No export name is
   assumed to exist; `/kmq:probe_clothing` prints exactly what the installed build
   exposes.
5. **No Rockstar-extracted files are committed.** The pipeline consumes a local,
   git-ignored `extracted/` input directory on the workstation and emits generated
   artifacts into git-ignored `build/` output; only manifests/reports (pure metadata)
   are committable.
