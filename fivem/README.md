# LifeCore — FiveM Framework

A lightweight, self-contained roleplay framework core for [FiveM](https://fivem.net) servers. It handles the plumbing every server needs — persistent players, money, jobs, items, callbacks — with a small, readable codebase you can actually extend.

```
fivem/
├── README.md
├── server.cfg.example          # Config snippets to merge into your server.cfg
├── sql/
│   └── lifecore.sql            # Database schema (MySQL/MariaDB)
└── resources/
    └── [lifecore]/
        ├── lifecore/           # The framework core
        │   ├── fxmanifest.lua
        │   ├── config.lua
        │   ├── shared/         # utils, service registry, job definitions, item registry
        │   ├── server/         # player lifecycle, API, callbacks, commands
        │   └── client/         # spawn/state sync, API, callbacks
        ├── lifecore-hud/       # Modern NUI HUD (status bars, money, toasts)
        └── lifecore-example/   # Reference resource built on the core
```

## Architecture: services, not spaghetti

The classic FiveM failure mode: resources call each other's exports directly, so swapping your inventory or phone breaks every script that touched it, and you spend a day chasing bugs. LifeCore prevents that structurally with a **service registry** — named modules behind stable contracts.

Consumers never name a concrete resource. They ask the core:

```lua
local inv = exports['lifecore']:GetService('inventory')
inv.AddItem(source, 'water', 1)
```

Providers register an implementation fulfilling the contract (missing methods are rejected loudly at registration time, not at call time three resources away):

```lua
exports['lifecore']:RegisterService('inventory', {
    AddItem      = function(source, item, count) ... end,
    RemoveItem   = function(source, item, count) ... end,
    GetItemCount = function(source, item) ... end,
})
```

Swap the providing resource — a custom inventory, an ox_inventory bridge, anything — and **no other resource changes**. When a providing resource stops, its services are automatically unregistered, so consumers get a clean `nil` instead of calling into a dead resource. Contracts currently defined (in `shared/services.lua`): `inventory` (server), and `notify`, `progress`, `target`, `phone`, `fuel` (client).

Two providers ship out of the box, proving the pattern end to end:

- the core registers its **built-in player inventory** as the default `inventory` provider;
- `lifecore-hud` registers itself as the `notify` provider — the moment it starts, every `LifeCore.Notify` in the entire framework renders as a HUD toast instead of a chat line, with zero changes anywhere else. Stop the HUD and notifications fall back to chat.

The HUD itself is fully push-based: state changes are forwarded to the NUI as they happen, and the only polling is a 250 ms tick for health/armor (which have no event) — no per-frame `Wait(0)` loops eating frame time.

## Features

- **Persistent players** — money, job, inventory, metadata, and position saved to MySQL (via [oxmysql](https://github.com/overextended/oxmysql)); loaded on join, saved on drop, autosaved on an interval, and saved on resource stop.
- **Money accounts** — `cash` and `bank`, with safe add/remove APIs and a `/pay` command.
- **Jobs & grades** — defined once in `shared/jobs.lua`, with salaries paid on a timer and boss grades.
- **Items** — registry in `shared/items.lua`, stackable/non-stackable, usable items with server-side handlers (`RegisterUsableItem`).
- **Hunger & thirst** — server-side decay, client-side health drain at zero, restored by consumables.
- **Server↔client callbacks** — request/response with correlation IDs, both async (`TriggerCallback`) and await (`AwaitCallback`) styles.
- **State sync** — every mutation pushes only the changed slice to the owning client; resources subscribe via `lifecore:client:playerUpdated`.
- **ACE-permission admin commands** — `/setjob`, `/givemoney`, `/giveitem`, `/saveall`.

## Installation

1. **Database** — create a database and import the schema:
   ```bash
   mysql -u user -p lifecore < sql/lifecore.sql
   ```
2. **oxmysql** — download [oxmysql](https://github.com/overextended/oxmysql/releases) into your server's `resources/` folder.
3. **Resources** — copy `resources/[lifecore]` into your server's `resources/` folder.
4. **server.cfg** — merge the relevant lines from `server.cfg.example`: the `mysql_connection_string`, `ensure oxmysql`, `ensure [lifecore]`, and the ACE permission for admins.
5. Start the server. New players are created automatically on first join.

## Using the framework from your own resources

Grab the core object through the export (works on both sides):

```lua
local LifeCore = exports['lifecore']:GetCore()
```

### Server API

```lua
local player = LifeCore.GetPlayer(source)     -- player object, nil if not loaded
LifeCore.GetPlayerByIdentifier('license:..')  -- lookup by identifier
LifeCore.GetPlayers()                         -- all loaded players
LifeCore.GetPlayersByJob('police')            -- filter by job
LifeCore.SaveAll()                            -- persist everyone now

-- Player object
player.GetMoney('cash')                       -- number
player.AddMoney('bank', 500)                  -- boolean success
player.RemoveMoney('cash', 100)               -- false if insufficient
player.SetJob('police', 2)                    -- false if job/grade unknown
player.GetJob()                               -- { name, label, grade, gradeLabel, salary, isboss }
player.AddItem('water', 3)                    -- false for unknown items
player.RemoveItem('water', 1)                 -- false if too few
player.GetItemCount('water')                  -- number
player.GetMetadata('hunger')                  -- any stored value
player.SetMetadata('licenses', { driver = true })
player.Save()                                 -- persist this player

-- Callbacks & usable items
LifeCore.RegisterCallback('myres:getData', function(source, cb, arg)
    cb(result)
end)
LifeCore.RegisterUsableItem('bandage', function(source) ... end)
```

### Client API

```lua
LifeCore.GetPlayerData()        -- { name, money, job, inventory, metadata, ... }
LifeCore.IsPlayerLoaded()       -- boolean
LifeCore.UseItem('water')       -- ask the server to consume an item
LifeCore.Notify('Hello!')       -- chat notification

LifeCore.TriggerCallback('myres:getData', function(result) ... end, arg)
local result = LifeCore.AwaitCallback('myres:getData', arg) -- inside a thread
```

### Events

| Event | Side | Fired when |
|---|---|---|
| `lifecore:server:playerLoaded` (`source, player`) | server | a player's state is loaded |
| `lifecore:server:playerDropped` (`source, identifier, reason`) | server | a player disconnects (after save) |
| `lifecore:server:jobChanged` (`source, name, grade`) | server | a player's job changes |
| `lifecore:client:loaded` (`data`) | client | initial state arrives |
| `lifecore:client:playerUpdated` (`key, value`) | client | any state slice changes |

The `lifecore-example` resource demonstrates all of the above end to end.

## Commands

| Command | Who | Description |
|---|---|---|
| `/status` | everyone | show cash, bank, hunger, thirst |
| `/use <item>` | everyone | consume a usable item |
| `/pay <id> <amount>` | everyone | give cash to another player |
| `/job` | everyone | show current job and grade |
| `/setjob <id> <job> <grade>` | admin (ACE) | set a player's job |
| `/givemoney <id> <cash\|bank> <amount>` | admin (ACE) | grant money |
| `/giveitem <id> <item> [count]` | admin (ACE) | grant items |
| `/saveall` | admin (ACE) | force-save all players |

## Configuration

Everything tunable lives in `resources/[lifecore]/lifecore/config.lua`: spawn point, starting money, default job, identifier type (`license`/`steam`/`discord`), autosave interval, and hunger/thirst decay rates. Jobs and items are data-driven — edit `shared/jobs.lua` and `shared/items.lua`, no code changes required.
