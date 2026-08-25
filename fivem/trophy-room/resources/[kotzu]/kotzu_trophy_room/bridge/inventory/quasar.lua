--[[
    Inventory bridge: qs-inventory (Quasar, server side).

    qs-inventory is a paid, closed-source resource, so unlike ox/qb this bridge
    cannot be verified against published source. Two consequences shape it:

    1. **Every export is resolved at RUNTIME** from a candidate list — the first
       one that actually exists wins (Bridge.ResolveExport CALLS the export;
       indexing a missing export never raises in FiveM). If your build names
       something differently, add the name to the list — no other change needed.
    2. **`/kmq:bridges` prints what resolved**, so the operator can see exactly
       which export names this server is using before trusting weapon displays.

    Confirmed from Quasar's public docs:
        AddItem(source, item, count[, slot, metadata])
        RemoveItem(source, item, count[, slot, metadata])
    Read paths are candidate-resolved because the docs differ across versions.
]]

local RES = 'qs-inventory'
local resolved = {}

local CANDIDATES = {
    -- whole inventory (preferred: lets us match metadata ourselves)
    getInventory = { 'GetInventory', 'getInventory', 'GetPlayerInventory' },
    -- single-item lookup, used only if no full-inventory export exists
    getItem      = { 'GetItemByName', 'getItemByName', 'GetItem' },
    addItem      = { 'AddItem', 'addItem' },
    removeItem   = { 'RemoveItem', 'removeItem' },
}

local function resolve(kind, probeArgs)
    return KTR.Bridge.ResolveExport(resolved, kind, RES, CANDIDATES[kind], probeArgs)
end

local impl = {
    detect = function() return KTR.Started(RES) end,
}

function impl.Functional()
    -- weapons need both a read path and both mutations
    local canRead = resolve('getInventory', { 1 }) or resolve('getItem', { 1, 'water' })
    return canRead ~= nil
        and resolve('removeItem', nil) ~= nil
        and resolve('addItem', nil) ~= nil
end

local function metadataOf(item)
    -- qs-inventory carries per-slot data as `info` (qb heritage) or `metadata`
    return item.info or item.metadata or {}
end

local function matches(item, want)
    if not want then return true end
    local md = metadataOf(item)
    for k, v in pairs(want) do
        if md[k] ~= v then return false end
    end
    return true
end

---@return table|nil { name, slot, metadata, count }
function impl.FindItem(src, name, metadata)
    local invExport = resolve('getInventory', { src })
    if invExport then
        local ok, inv = KTR.Bridge.TryExport(RES, invExport, src)
        if ok and type(inv) == 'table' then
            -- qs returns either an array of slots or a slot-keyed map
            for slot, item in pairs(inv) do
                if type(item) == 'table' and item.name == name and matches(item, metadata) then
                    return {
                        name = item.name,
                        slot = item.slot or (type(slot) == 'number' and slot) or nil,
                        metadata = metadataOf(item),
                        count = item.amount or item.count or 1,
                    }
                end
            end
            return nil
        end
    end

    local getExport = resolve('getItem', { src, name })
    if getExport then
        local ok, item = KTR.Bridge.TryExport(RES, getExport, src, name)
        if ok and type(item) == 'table' and matches(item, metadata) then
            return {
                name = item.name or name,
                slot = item.slot,
                metadata = metadataOf(item),
                count = item.amount or item.count or 1,
            }
        end
    end
    return nil
end

---Count matching items. Used to VERIFY mutations instead of trusting a return
---value: qs builds differ in what they return (true / nil / the item), and
---guessing here would either lose an item (assumed success that failed) or
---duplicate one (assumed failure that succeeded).
local function countMatching(src, name, metadata)
    local invExport = resolve('getInventory', { src })
    if not invExport then return nil end -- cannot verify
    local ok, inv = KTR.Bridge.TryExport(RES, invExport, src)
    if not ok or type(inv) ~= 'table' then return nil end
    local n = 0
    for _, item in pairs(inv) do
        if type(item) == 'table' and item.name == name and matches(item, metadata) then
            n = n + (item.amount or item.count or 1)
        end
    end
    return n
end

function impl.RemoveItem(src, name, slot, metadata)
    local exportName = resolve('removeItem', nil)
    if not exportName then return false end
    local before = countMatching(src, name, metadata)
    -- documented signature: RemoveItem(source, item, count, slot, metadata)
    local ok, res = KTR.Bridge.TryExport(RES, exportName, src, name, 1, slot, metadata)
    if not ok then return false end
    if res == false then return false end
    if before == nil then
        -- no read path to verify with: trust only an explicit truthy result
        return res == true
    end
    local after = countMatching(src, name, metadata)
    return after ~= nil and after == before - 1
end

function impl.AddItem(src, name, metadata)
    local exportName = resolve('addItem', nil)
    if not exportName then return false end
    local before = countMatching(src, name, metadata)
    local ok, res = KTR.Bridge.TryExport(RES, exportName, src, name, 1, nil, metadata)
    if not ok then return false end
    if res == false then return false end
    if before == nil then
        return res == true
    end
    -- a full inventory can silently drop the add; verify the count actually rose
    local after = countMatching(src, name, metadata)
    return after ~= nil and after == before + 1
end

function impl.Describe()
    return {
        resource = RES,
        resolvedExports = resolved,
        functional = impl.Functional(),
    }
end

-- priority 30: above ox (20) and qb (10) so an explicit qs install wins
KTR.Bridge.Register('inventory', 'qs-inventory', 30, impl)
