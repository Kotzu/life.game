--[[
    Clothing bridge: rcore_clothing (client).

    rcore_clothing is a paid resource whose export surface differs between
    versions, so NOTHING here assumes an export exists: every integration point
    is a probe list tried with pcall at init, and the resolved capability map is
    logged + queryable via /kmq:probe_clothing. Capture always works because the
    normalized outfit comes from the native layer; rcore adds (a) its raw
    snapshot for lossless round-trips and (b) saved-outfit enumeration when the
    installed build exposes it.

    If your rcore build exposes different export names, add them to the probe
    lists below — one line per candidate, no other changes needed.
]]

local natives -- resolved lazily from the registry

local PROBES = {
    -- each entry: list of { name = exportName, call = function wrapper }
    getCurrentSnapshot = { 'getPlayerCurrentClothes', 'getCurrentClothes', 'getPlayerSkin', 'exportPlayerSkin' },
    getSavedOutfits    = { 'getPlayerOutfits', 'getOutfits', 'getSavedOutfits' },
    getOutfitById      = { 'getOutfit', 'getPlayerOutfit' },
}

local caps = nil -- resolved capability map: capName -> exportName|false

local function probe()
    caps = {}
    for capName, candidates in pairs(PROBES) do
        caps[capName] = false
        for _, exportName in ipairs(candidates) do
            local ok = pcall(function()
                -- probing with a harmless call; export missing raises
                local _ = exports.rcore_clothing[exportName]
                return true
            end)
            if ok then
                caps[capName] = exportName
                break
            end
        end
    end
    print(('[kotzu_trophy] rcore_clothing capabilities: %s'):format(json.encode(caps)))
    return caps
end

local function callCap(capName, ...)
    if not caps then probe() end
    local exportName = caps[capName]
    if not exportName then return nil, 'capability not available in installed rcore build' end
    local ok, res = pcall(function(...)
        return exports.rcore_clothing[exportName](nil, ...)
    end, ...)
    if not ok then return nil, tostring(res) end
    return res
end

local impl = {
    detect = function() return KTR.Started('rcore_clothing') end,
    init = function() probe() end,
}

function impl.Capture(ped)
    natives = natives or KTR.Bridge.Find('clothing', 'natives')
    local outfit, err = natives.Capture(ped)
    if not outfit then return nil, err end
    local snap = callCap('getCurrentSnapshot')
    if snap ~= nil then
        outfit.raw = { source = 'rcore_clothing', data = snap }
    end
    return outfit
end

impl.Apply = function(ped, outfit)
    return KTR.Bridge.Find('clothing', 'natives').Apply(ped, outfit)
end

impl.ComponentExists = function(ped, compId, collection, drawable)
    return KTR.Bridge.Find('clothing', 'natives').ComponentExists(ped, compId, collection, drawable)
end

---Enumerate saved outfits if the installed rcore build supports it.
---@return table|nil list of { id, label }, nil+reason otherwise
function impl.GetSavedOutfits()
    local res, err = callCap('getSavedOutfits')
    if res == nil then return nil, err end
    local out = {}
    if type(res) == 'table' then
        for k, v in pairs(res) do
            out[#out + 1] = {
                id = (type(v) == 'table' and (v.id or v.outfitId)) or k,
                label = (type(v) == 'table' and (v.label or v.name or v.outfitname)) or tostring(k),
            }
        end
    end
    return out
end

function impl.Describe()
    if not caps then probe() end
    return caps
end

KTR.Bridge.Register('clothing', 'rcore_clothing', 10, impl)
