-- FXServer environment shim (server side) for headless integration testing.
-- Provides the natives/globals the trophy-room SERVER scripts use, an event
-- system, a cooperative scheduler, resource-file access, and player fakes.
-- NOT a FiveM reimplementation — just enough to execute the real code paths.

local SIM = { events = {}, clientEvents = {}, commands = {}, players = {},
              buckets = {}, aces = {}, resources = {}, clock = 1000000 }
_G.FXSIM = SIM

json = require('json')

-- ------------------------------------------------------------------ vectors
local vecMt
vecMt = {
    __sub = function(a, b)
        return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vecMt)
    end,
    __len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end,
}
function vector3(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, vecMt)
end
function vector4(x, y, z, w)
    return setmetatable({ x = x, y = y, z = z, w = w }, vecMt)
end
function joaat(s) -- deterministic stand-in hash
    local h = 0
    for i = 1, #s do h = (h * 31 + s:byte(i)) % 2 ^ 32 end
    return h
end

function IsDuplicityVersion() return true end -- server side

-- ---------------------------------------------------------------- scheduler
function GetGameTimer() return SIM.clock end

function Wait(ms)
    SIM.clock = SIM.clock + math.max(ms or 0, 1)
    if coroutine.isyieldable() then coroutine.yield() end
end

-- Like FXServer, CreateThread defers to the "next tick": threads queue and run
-- via SIM.Drain() after script load (or after simulated events/commands).
SIM.threadQueue = {}

function CreateThread(fn)
    table.insert(SIM.threadQueue, fn)
end

function SIM.Drain()
    local guard = 0
    while #SIM.threadQueue > 0 do
        guard = guard + 1
        if guard > 1000 then error('thread queue not draining') end
        local fn = table.remove(SIM.threadQueue, 1)
        local co = coroutine.create(fn)
        local steps = 0
        repeat
            steps = steps + 1
            local ok, err = coroutine.resume(co)
            if not ok then error('thread error: ' .. tostring(err)) end
        until coroutine.status(co) == 'dead' or steps > 100000
    end
end

-- ------------------------------------------------------------------- events
function RegisterNetEvent(name, fn)
    if fn then
        SIM.events[name] = SIM.events[name] or {}
        table.insert(SIM.events[name], fn)
    end
end

function AddEventHandler(name, fn)
    RegisterNetEvent(name, fn)
end

function TriggerEvent(name, ...)
    for _, fn in ipairs(SIM.events[name] or {}) do fn(...) end
end

function TriggerClientEvent(name, src, ...)
    table.insert(SIM.clientEvents, { name = name, src = src, args = { ... } })
end

---Simulate a client firing a net event (sets the `source` global like FXServer).
function SIM.FromClient(name, src, ...)
    for _, fn in ipairs(SIM.events[name] or {}) do
        _G.source = src
        fn(...)
        _G.source = nil
    end
end

function SIM.LastClientEvent(name, src)
    for i = #SIM.clientEvents, 1, -1 do
        local e = SIM.clientEvents[i]
        if e.name == name and (src == nil or e.src == src) then return e end
    end
    return nil
end

-- ----------------------------------------------------------------- players
function SIM.AddPlayer(src, opts)
    opts = opts or {}
    SIM.players[src] = {
        name = opts.name or ('Sim%d'):format(src),
        license = opts.license or ('license:sim%d'):format(src),
    }
    SIM.buckets[src] = opts.bucket or 0
    SIM.aces[src] = opts.aces or {}
end

function GetPlayers()
    local out = {}
    for src in pairs(SIM.players) do out[#out + 1] = tostring(src) end
    table.sort(out)
    return out
end

function GetPlayerRoutingBucket(src) return SIM.buckets[src] or 0 end
function SetPlayerRoutingBucket(src, b) SIM.buckets[src] = b end
function GetPlayerPed(_) return 0 end
function GetPlayerName(src)
    local p = SIM.players[src]
    return p and p.name or nil
end
function GetNumPlayerIdentifiers(_) return 1 end
function GetPlayerIdentifier(src, _)
    local p = SIM.players[src]
    return p and p.license or nil
end
function IsPlayerAceAllowed(src, ace)
    return (SIM.aces[src] or {})[ace] == true
end

-- --------------------------------------------------------------- resources
function SIM.RegisterResource(name, dir) SIM.resources[name] = dir end

function GetResourceState(name)
    return SIM.resources[name] and 'started' or 'missing'
end

function GetCurrentResourceName() return SIM.currentResource or 'kotzu_trophy_room' end

function LoadResourceFile(res, path)
    local dir = SIM.resources[res]
    if not dir then return nil end
    local f = io.open(dir .. '/' .. path, 'r')
    if not f then return nil end
    local data = f:read('a')
    f:close()
    return data
end

function SaveResourceFile(res, path, data, _)
    local dir = SIM.resources[res]
    if not dir then return false end
    local f = io.open(dir .. '/' .. path, 'w')
    if not f then return false end
    f:write(data)
    f:close()
    return true
end

function RegisterCommand(name, fn, restricted)
    SIM.commands[name] = { fn = fn, restricted = restricted }
end

-- exports: callable to register, indexable for cross-resource calls.
-- External resources (qbx_core, ox_inventory, ...) can be faked with
-- SIM.RegisterExternalExports; colon-call convention (self stripped) matched.
local exportsRegistry = {}
local externalExports = {}

function SIM.RegisterExternalExports(res, tbl)
    externalExports[res] = tbl
end

exports = setmetatable({}, {
    __call = function(_, name, fn) exportsRegistry[name] = fn end,
    __index = function(_, res)
        local ext = externalExports[res]
        return setmetatable({}, { __index = function(_, fnName)
            if ext and ext[fnName] then
                return function(_, ...) return ext[fnName](...) end
            end
            return function() error(('export %s.%s not available in sim'):format(res, fnName)) end
        end })
    end,
})
SIM.exports = exportsRegistry

-- ------------------------------------------------------------- script load
function SIM.LoadScripts(resourceName, baseDir, files)
    SIM.currentResource = resourceName
    for _, rel in ipairs(files) do
        local chunk, err = loadfile(baseDir .. '/' .. rel)
        if not chunk then error('load ' .. rel .. ': ' .. tostring(err)) end
        local ok, runErr = pcall(chunk)
        if not ok then error('exec ' .. rel .. ': ' .. tostring(runErr)) end
    end
end

return SIM
