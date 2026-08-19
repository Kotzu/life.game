# Security Review

Scope: `kotzu_trophy_room` + `kotzu_mannequin_assets` + `kotzu_arch_proof`.
Model: every client event/RPC is attacker-controlled (brief §18).

## Trust boundaries

1. **Client → Server RPC** (`shared/rpc.lua` → handlers in `server/main.lua`) — the only
   mutation path. There are no other writable net events.
2. **Server → DB** via oxmysql prepared statements (parameterized everywhere; no string
   concatenation of values — the single dynamic SQL in `repository.Update` interpolates
   only a server-built column list, never client data).
3. **NUI → client Lua** — NUI callbacks clamp/normalize strings before RPC.

## Controls by threat

| Threat | Control | Where |
|---|---|---|
| Forged ownership / owner-id spoofing | owner always derived from server framework identity, never from payload | `main.lua displays:place` (`d.owner = id.citizenid`) |
| Escalation to others' displays | capability check per action (owner / housing co-owner / job+grade / admin ace) | `permissions.lua` |
| Scope forgery (placing into someone's property) | housing resolver authorizes scopeType/scopeId per player | `Perms.CanPlaceInScope`, `housing.ResolveScope` |
| Bucket spoofing / cross-instance leak | routing bucket read server-side (`GetPlayerRoutingBucket`), never from client; queries + broadcasts filtered by bucket | `validation.lua`, `main.lua` |
| Teleported/remote placement | world-position distance check vs server-observed ped position | `Validate.DisplayInput` |
| Oversized/hostile payloads | 16 KB encoded cap before deep validation; strict schema (types, ranges, collection-name charset, component/prop count caps) | `schemas.lua`, `validation.lua` |
| Garbage models/components | pose + platform whitelists; display types enum; component tuples validated against schema, and against manifest for mannequins | `validation.lua` |
| Entity spam | per-scope and per-owner display caps; client max-visible cap | `Limits`, `streaming.lua` |
| Event flooding | per-player sliding-window rate limits on every RPC | `ratelimit.lua` |
| Weapon duplication | idempotency-keyed lock table, ordered state machine (side effect recorded before next step), soft-delete-as-lock on retrieve, compensation, startup recovery, audit log; item metadata taken from the FOUND inventory item (client metadata is only a filter); serial required | `transactions.lua`, `sql/002` |
| Client-supplied item metadata/prices | never trusted; server re-reads inventory | `transactions.lua` |
| Arbitrary code execution | no `load`/`loadstring`/dynamic Lua anywhere; NUI is static, dependency-free | repo-wide (grep-verified) |
| Evidence forgery via arch-proof writer | submission gated by ace (`command` / `kotzu.archproof`) | `kotzu_arch_proof/server` |
| Harness abuse on live | `Config.DevCommands=false` disables all `/kmq:*`; server harness additionally requires admin ace | both harness files |
| Try-on stuck outfit | restore on timeout/cancel/death/resource-stop + KVP crash recovery | `preview.lua` |

## Residual risks / notes for the operator

1. **`failed_item_lost` lock state** (place: item removed, display insert failed, AND
   compensation AddItem failed — e.g. inventory full at that exact moment): logged +
   audited; admin must hand the item back. Surfaced by `/kmq:validate_db`.
2. **rcore raw snapshots** are stored opaquely inside outfit JSON (size-capped). They are
   never executed or applied blindly — only the validated normalized form drives peds.
3. `kmq:testshell` moves routing buckets — dev-gated + admin ace; keep DevCommands off
   in production.
4. SQL migrations run with the resource's DB user; grant only CREATE/ALTER on the
   game database, nothing global.
5. The NUI never receives other players' identifying data; `publicView()` whitelists
   fields (no owner citizenid is broadcast to clients).
