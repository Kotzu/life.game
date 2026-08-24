# Anti-Duplication Analysis — Weapons & Clothing

Adversarial review of every path that could duplicate an item or transfer value.
Model: FiveM server Lua is **cooperative** — `MySQL.*.await` and inventory-bridge
calls yield, so two events from the same player can interleave at each yield.

## Clothing / outfits — NO economy dupe (by construction)

Grep-verified: the only `AddItem`/`RemoveItem` calls in the whole resource are in
`server/transactions.lua` (weapons). Outfit RPCs (`outfit:forTryOn`,
`outfit:savedList`, `outfit:savedGet`) and outfit capture return **data only**.

| Path | Why it can't dupe |
|---|---|
| Capture worn outfit → mannequin | copies component indexes (cosmetic); your clothes are untouched |
| Try-on (visitor) | temporary; restored on timeout/cancel/death/resource-stop + KVP crash recovery |
| Saved outfit apply | read-only lookup from `player_outfits`, ownership enforced in SQL |
| Change/rename/pose/move | metadata only, no item transfer |

Rare-item / achievement displays are **decorative metadata** — placing one does
NOT remove an inventory item, so deleting one cannot create value. ⚠️ If a future
change ties rare items to real inventory items, they MUST go through the weapon
transaction path (`Tx.PlaceWeapon`/`RetrieveWeapon`), not `Repo.Create`/`Delete`.

## Weapons — enumerated dupe vectors and their defenses

| # | Vector | Defense | Test |
|---|---|---|---|
| W1 | **Concurrent place of the same physical weapon** (two `displays:place`, different idempotency keys, interleaving between `FindItem` and `RemoveItem`) | **Synchronous per-citizen critical-section lock** acquired before the first yield (`acquire(citizenid)`), serializing a player's weapon ops; the second runs only after the first commits | S14 (lock present) + S7 |
| W2 | Same weapon lands on two live displays (any residual race, restart edge, logic slip) | **`Repo.SerialInUse`** checked inside the critical section — a serial already on a live display refuses the second place with `DUPLICATE` (+ audit `weapon_dupe_blocked`) | S14 |
| W3 | Replay of a place request | idempotency lock (`kotzu_tx_locks`, INSERT-IGNORE gate): a replay returns the stored outcome, never re-executes | S7 |
| W4 | Concurrent retrieve of one display (owner + admin/co-owner) | **soft-delete-as-lock**: atomic `UPDATE … WHERE deleted_at IS NULL` affected-rows; only one caller flips it, so `AddItem` runs once | S7 |
| W5 | Spam retrieve by one player | per-citizen lock + soft-delete guard | S7 |
| W6 | Place → retrieve → re-place (serial re-use) | legitimate: cache holds only live rows, so a retrieved serial is freed and re-placeable | S14 |
| W7 | Retrieve into a full inventory | `AddItem` fails → row **restored** (no loss, no dupe) | S7 (compensation) |
| W8 | Place with item removed but display insert fails | `AddItem` compensation returns the item; `failed_item_lost` audited if even that fails | S7 |
| W9 | Client spoofs cheaper/other item via metadata | client metadata is only a narrowing **filter**; the FOUND item's metadata is authoritative; a serial is required or `BAD_INPUT` | S8-style |
| W10 | Delete a weapon display to bypass retrieval transaction | `displays:delete` refuses `weapon_*` types → must use `weapons:retrieve` | S-delete |
| W11 | Crash mid-transaction | ordered state machine + startup `RecoverStranded` (item-removed → recovery credit; row-deleted → restore) | S9 |
| W12 | Idempotency-key collision/garbage | `validKey` (8–64, `[%w-_]`); rate limit `weapon_tx` 6/min | — |

## Residual risk & hardening notes

- **Single-server assumption.** `SerialInUse` scans the in-memory registry, which
  is authoritative per server. For a **multi-server cluster sharing one DB**, add a
  DB-level guard: a dedicated `item_serial` column with a UNIQUE index, NULLed on
  soft-delete so retrieved serials free up. Documented here rather than shipped,
  because this resource's registry model is per-server.
- The per-citizen lock also serializes a player's place vs. retrieve (returns
  `RATE_LIMITED` if one is mid-flight) — intentional and safe.
- All dupe attempts and compensations are written to `kotzu_display_audit`;
  `/kmq:validate_db` surfaces cache/DB/lock inconsistencies and stale locks.

Verified headlessly: `tools/fxsim` scenarios **S7, S8, S9, S14, S15** — 51/51
checks pass on real MariaDB.
