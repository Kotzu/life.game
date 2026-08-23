--[[
    Clothing bridge: illenium-appearance (client) — the standard appearance
    resource on Qbox setups.

    Verified against the real source (github.com/iLLeniumStudios/illenium-appearance):
    - saved outfits live in the `player_outfits` table
      (citizenid, outfitname, model, components JSON, props JSON)
    - payload shape: components = [{component_id, drawable(GLOBAL), texture}],
      props = [{prop_id, drawable(GLOBAL), texture}]

    Saved-outfit listing/fetch is done SERVER-side from that table (RPCs
    outfit:savedList / outfit:savedGet in server/main.lua) — no fragile client
    export probing. Payloads are normalized to the v2 schema on the client via
    the global->collection lookup natives (natives.NormalizeIllenium).
]]

local function nativesImpl()
    for _, i in ipairs(KTR.Bridge._impls.clothing) do
        if i.__name == 'natives' then return i end
    end
end

local impl = {
    detect = function() return KTR.Started('illenium-appearance') end,
}

function impl.Capture(ped)
    local n = nativesImpl()
    local outfit, err = n.Capture(ped)
    if not outfit then return nil, err end
    outfit.raw = { source = 'illenium-appearance' }
    return outfit
end

function impl.Apply(ped, outfit)
    return nativesImpl().Apply(ped, outfit)
end

function impl.ComponentExists(ped, compId, collection, drawable)
    return nativesImpl().ComponentExists(ped, compId, collection, drawable)
end

---@return table|nil list of { id, label, model }
function impl.GetSavedOutfits()
    local res, err = KTR.RPC.Call('outfit:savedList', {})
    if not res then return nil, err end
    return res.outfits
end

---Fetch + normalize one saved outfit for a target gender.
---@return table|nil outfit (v2), string|nil err
function impl.GetSavedOutfit(outfitId, gender)
    local res, err = KTR.RPC.Call('outfit:savedGet', { id = outfitId })
    if not res then return nil, err end
    local model = KTR.Const.Model[gender]
    if res.model ~= model then return nil, KTR.Const.Err.OUTFIT_INVALID end
    return nativesImpl().NormalizeIllenium(res.model, res.components, res.props)
end

KTR.Bridge.Register('clothing', 'illenium-appearance', 20, impl)
