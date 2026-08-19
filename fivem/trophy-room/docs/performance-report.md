# Performance Report

**Status: NOT YET MEASURED.** This project does not invent performance numbers
(brief §19). Fill the tables below on the sandbox using the procedure given; keep the
raw resmon screenshots in `captures/perf/`.

## Design budget (targets, not measurements)

| Metric | Target |
|---|---|
| Idle client (`kotzu_trophy_room`, resmon) | ≤ 0.05 ms |
| Active placement mode | ≤ 0.30 ms (single per-frame loop, only while placing) |
| Scan tick (1 s cadence) | ≤ 0.2 ms spike per tick at 50 registered displays |
| Server think | ≤ 0.05 ms idle; RPCs O(1) per call |
| Mannequin spawn cost | amortized by 4-per-tick batching |
| Streamed assets | ≤ 16 MB per .ydd, ≤ 32 MB per .ytd (pipeline `validate` warns) |

Structural guarantees behind the targets: no `Wait(0)` loops outside active placement
and the fallback-target prompt; streaming is a 1 Hz scan over an in-memory table;
broadcasts fan out only to same-bucket players; DB access only on mutations + startup.

## Measurement procedure

1. `resmon 1` on client; note baseline with 0 displays. Screenshot.
2. Place N mannequins in a test shell via `/kmq:testshell a` + `/trophyroom`
   (or restore a prepared DB fixture); record resmon idle standing among them, then
   while walking the spawn boundary (stream churn), for N = 1, 10, 25, 50.
3. Placement mode active: resmon while moving a ghost.
4. Server: txAdmin performance page / `profiler record 500` during step 2 churn.
5. Two clients in the same shell: repeat N=25; confirm identical resmon class.
6. Two buckets (`/kmq:testshell a` vs `b`): confirm client in B shows zero cost from
   A's displays (`/kmq:debug` → registry=0 for A's scope).
7. Memory: `resmon` memory column + `str list` for `kotzu_mannequin_assets` streaming
   size before/after entering the room.

## Results (fill in)

| Scenario | Client ms (idle) | Client ms (churn) | Server ms | Memory |
|---|---|---|---|---|
| 0 displays | | | | |
| 1 display | | | | |
| 10 displays | | | | |
| 25 displays | | | | |
| 50 displays | | | | |
| placement active | | | | |
| 2 clients, 25 displays | | | | |
| 2 buckets isolation | | | | |

| Asset | Size on disk | Streaming size |
|---|---|---|
| mannequin body set (per gender) | | |
| converted garments (total) | | |

Recorded by: ______ · Date: ______ · Game build: ______ · Hardware: ______
