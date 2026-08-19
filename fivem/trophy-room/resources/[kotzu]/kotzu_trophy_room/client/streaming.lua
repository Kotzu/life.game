--[[
    Client streaming (brief §9): deterministic local entities from server
    registry data. One scan thread at Config.Streaming.ScanIntervalMs; no
    per-frame work. Spawns are batched; despawn uses hysteresis; entities are
    keyed by uid so re-streams and reconnects can never duplicate.
]]

KTRC = KTRC or {}
KTRC.Streaming = {}
local S = KTRC.Streaming
local C = KTR.Const

local registry = {}   -- uid -> display record (server truth, world scope + current room)
local spawned = {}    -- uid -> renderer handle
local scopeKey = nil  -- current scope identity, to detect room changes

function S.Registry() return registry end
function S.Spawned() return spawned end

function S.EntityFor(uid)
    local h = spawned[uid]
    return h and h.entities[1] or nil
end

function S.DisplayForEntity(entity)
    for uid, h in pairs(spawned) do
        for _, e in ipairs(h.entities) do
            if e == entity then return registry[uid], h end
        end
    end
    return nil
end

local function worldTransform(display)
    local housing = KTR.Bridge.Get('housing')
    if display.scopeType == C.ScopeType.WORLD or not housing then
        return display.transform
    end
    return housing.ToWorld(display)
end

local function despawn(uid)
    local handle = spawned[uid]
    if not handle then return end
    local renderer = KTRC.Renderers.Get(registry[uid] and registry[uid].displayType or '')
    if renderer then
        renderer.despawn(handle)
    else
        for _, e in ipairs(handle.entities or {}) do
            if DoesEntityExist(e) then DeleteEntity(e) end
        end
    end
    if KTRC.Interaction then KTRC.Interaction.OnDespawn(uid, handle) end
    spawned[uid] = nil
end

function S.DespawnAll()
    for uid in pairs(spawned) do despawn(uid) end
end

function S.Refresh(uid)
    despawn(uid)
    -- the scan thread respawns it next tick if in range
end

function S.RefreshAll()
    S.DespawnAll()
end

-- ------------------------------------------------------------ registry sync

local function currentScope()
    local housing = KTR.Bridge.Get('housing')
    local room = housing and housing.CurrentRoom and housing.CurrentRoom()
    if room then
        return room.scopeType, room.scopeId
    end
    return C.ScopeType.WORLD, nil
end

function S.RequestScope()
    local scopeType, scopeId = currentScope()
    local list, err = KTR.RPC.Call('displays:listScope',
        { scopeType = scopeType, scopeId = scopeId })
    if not list then
        if KTR.Config.Debug then print('[kotzu_trophy] listScope failed: ' .. tostring(err)) end
        return false
    end
    -- replace registry entries for this scope wholesale (deterministic recreate)
    for uid, d in pairs(registry) do
        if d.scopeType == scopeType then registry[uid] = nil despawn(uid) end
    end
    for _, d in ipairs(list) do registry[d.uid] = d end
    scopeKey = ('%s|%s'):format(scopeType, tostring(scopeId))
    return true
end

RegisterNetEvent('kotzu_trophy:display:upsert', function(d)
    if type(d) ~= 'table' or type(d.uid) ~= 'string' then return end
    registry[d.uid] = d
    despawn(d.uid) -- respawn with fresh data next tick if in range
end)

RegisterNetEvent('kotzu_trophy:display:delete', function(uid)
    if type(uid) ~= 'string' then return end
    despawn(uid)
    registry[uid] = nil
end)

AddEventHandler('kotzu_trophy:room:entered', function()
    S.RequestScope()
end)

AddEventHandler('kotzu_trophy:room:exited', function()
    -- drop shell/property records; world records persist
    for uid, d in pairs(registry) do
        if d.scopeType ~= C.ScopeType.WORLD then
            despawn(uid)
            registry[uid] = nil
        end
    end
    S.RequestScope()
end)

-- --------------------------------------------------------------- scan loop

CreateThread(function()
    while true do
        Wait(KTR.Config.Streaming.ScanIntervalMs)
        local cfg = KTR.Config.Streaming
        local ppos = GetEntityCoords(PlayerPedId())

        -- candidates by distance
        local want = {}
        for uid, d in pairs(registry) do
            local t = worldTransform(d)
            local dist = #(ppos - vector3(t.x, t.y, t.z))
            if spawned[uid] then
                if dist > cfg.DespawnRadius then
                    despawn(uid)
                end
            elseif dist <= cfg.SpawnRadius then
                want[#want + 1] = { uid = uid, dist = dist, t = t }
            end
        end
        table.sort(want, function(a, b) return a.dist < b.dist end)

        local visible = 0
        for _ in pairs(spawned) do visible = visible + 1 end

        local budget = cfg.SpawnBatchSize
        for _, cand in ipairs(want) do
            if budget <= 0 or visible >= cfg.MaxVisibleDisplays then break end
            local d = registry[cand.uid]
            if d and not spawned[cand.uid] then
                local renderer = KTRC.Renderers.Get(d.displayType)
                if renderer then
                    local handle, err = renderer.spawn(d, cand.t)
                    if handle then
                        spawned[cand.uid] = handle
                        visible = visible + 1
                        if KTRC.Interaction then KTRC.Interaction.OnSpawn(d, handle) end
                    elseif KTR.Config.Debug then
                        print(('[kotzu_trophy] spawn failed %s: %s'):format(cand.uid, tostring(err)))
                    end
                    budget = budget - 1
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        S.DespawnAll()
    end
end)
