--[[
    Clothing bridge: native capture/apply (client).
    Always available; the rcore bridge layers on top of this and attaches the
    rcore raw snapshot when the installed rcore build exposes one.

    Normalization prefers (collectionName, localIndex) over global indexes
    (ADR-001 E3) so payloads survive addon-pack reordering between restarts.
]]

local C = KTR.Const

local impl = {
    detect = function() return true end,
}

---Capture the ped's current outfit into the normalized v2 schema.
function impl.Capture(ped)
    ped = ped or PlayerPedId()
    local model = GetEntityModel(ped)
    local gender
    if model == joaat(C.Model.male) then gender = C.Gender.MALE
    elseif model == joaat(C.Model.female) then gender = C.Gender.FEMALE
    else return nil, 'not a freemode ped' end

    local outfit = {
        schema = C.OUTFIT_SCHEMA,
        gender = gender,
        model = C.Model[gender],
        components = {},
        props = {},
        raw = { source = 'natives' },
    }

    for _, comp in ipairs(C.AllComponents) do
        local collection = GetPedDrawableVariationCollectionName(ped, comp) or ''
        local drawable = GetPedDrawableVariationCollectionLocalIndex(ped, comp)
        local texture = GetPedTextureVariation(ped, comp)
        local palette = GetPedPaletteVariation(ped, comp)
        if drawable == nil or drawable < 0 then
            collection, drawable = '', GetPedDrawableVariation(ped, comp)
        end
        outfit.components[tostring(comp)] = {
            collection = collection,
            drawable = drawable,
            texture = math.max(texture or 0, 0),
            palette = math.max(palette or 0, 0),
        }
    end

    for _, propId in ipairs(C.AllProps) do
        local globalIdx = GetPedPropIndex(ped, propId)
        if globalIdx == -1 then
            outfit.props[tostring(propId)] = { cleared = true }
        else
            local collection = GetPedPropCollectionName(ped, propId) or ''
            local localIdx = GetPedPropCollectionLocalIndex(ped, propId)
            if localIdx == nil or localIdx < 0 then collection, localIdx = '', globalIdx end
            outfit.props[tostring(propId)] = {
                collection = collection,
                drawable = localIdx,
                texture = math.max(GetPedPropTextureIndex(ped, propId) or 0, 0),
            }
        end
    end
    return outfit
end

---Apply a normalized outfit to a ped VERBATIM (no mannequin manifest logic —
---used for player try-on/restore; mannequins go through client/mannequin.lua).
function impl.Apply(ped, outfit)
    local ok, err = KTR.Schemas.ValidateOutfit(outfit)
    if not ok then return false, err end
    for k, comp in pairs(outfit.components) do
        local id = tonumber(k)
        if comp.collection and comp.collection ~= '' then
            SetPedCollectionComponentVariation(ped, id, comp.collection,
                comp.drawable, comp.texture, comp.palette or 0)
        else
            SetPedComponentVariation(ped, id, comp.drawable, comp.texture, comp.palette or 0)
        end
    end
    for k, prop in pairs(outfit.props or {}) do
        local id = tonumber(k)
        if prop.cleared then
            ClearPedProp(ped, id)
        elseif prop.collection and prop.collection ~= '' then
            SetPedCollectionPropIndex(ped, id, prop.collection, prop.drawable, prop.texture, true)
        else
            SetPedPropIndex(ped, id, prop.drawable, prop.texture, true)
        end
    end
    return true
end

---Normalize an illenium-appearance style payload (GLOBAL drawable indexes,
---components = [{component_id, drawable, texture}], props = [{prop_id, ...}])
---into the v2 schema using the global->collection lookup natives. Needs a ped
---of the target model to anchor the lookups; spawns a hidden temp ped when the
---player's model differs.
---@return table|nil outfit, string|nil err
function impl.NormalizeIllenium(model, rawComponents, rawProps)
    local C2 = KTR.Const
    local gender
    if model == C2.Model.male then gender = C2.Gender.MALE
    elseif model == C2.Model.female then gender = C2.Gender.FEMALE
    else return nil, 'unsupported model ' .. tostring(model) end

    local anchor = PlayerPedId()
    local temp = nil
    if GetEntityModel(anchor) ~= joaat(model) then
        local hash = joaat(model)
        RequestModel(hash)
        local deadline = GetGameTimer() + 8000
        while not HasModelLoaded(hash) do
            if GetGameTimer() > deadline then return nil, 'model load timeout' end
            Wait(25)
        end
        local p = GetEntityCoords(PlayerPedId())
        temp = CreatePed(4, hash, p.x, p.y, p.z - 50.0, 0.0, false, false)
        SetModelAsNoLongerNeeded(hash)
        if not DoesEntityExist(temp) then return nil, 'temp ped spawn failed' end
        SetEntityVisible(temp, false, false)
        FreezeEntityPosition(temp, true)
        anchor = temp
    end

    local outfit = {
        schema = C2.OUTFIT_SCHEMA, gender = gender, model = model,
        components = {}, props = {},
        raw = { source = 'illenium-appearance' },
    }
    for _, comp in ipairs(rawComponents or {}) do
        local id = tonumber(comp.component_id)
        local globalIdx = tonumber(comp.drawable) or 0
        if id ~= nil and id >= 0 and id <= 11 then
            local coll = GetPedCollectionNameFromDrawable(anchor, id, globalIdx) or ''
            local localIdx = GetPedCollectionLocalIndexFromDrawable(anchor, id, globalIdx)
            if localIdx == nil or localIdx < 0 then coll, localIdx = '', globalIdx end
            outfit.components[tostring(id)] = {
                collection = coll, drawable = localIdx,
                texture = math.max(tonumber(comp.texture) or 0, 0), palette = 0,
            }
        end
    end
    for _, prop in ipairs(rawProps or {}) do
        local id = tonumber(prop.prop_id)
        local globalIdx = tonumber(prop.drawable)
        if id ~= nil and id >= 0 and id <= 8 then
            if globalIdx == nil or globalIdx < 0 then
                outfit.props[tostring(id)] = { cleared = true }
            else
                -- prop global->local conversion native is not available; props in
                -- illenium payloads are global indexes, which SetPedPropIndex
                -- accepts directly, so store as base-collection global.
                outfit.props[tostring(id)] = {
                    collection = '', drawable = globalIdx,
                    texture = math.max(tonumber(prop.texture) or 0, 0),
                }
            end
        end
    end

    if temp and DoesEntityExist(temp) then DeleteEntity(temp) end
    local okV, errV = KTR.Schemas.ValidateOutfit(outfit)
    if not okV then return nil, 'normalized outfit invalid: ' .. tostring(errV) end
    return outfit
end

---Verify a component tuple actually exists on this ped model (anti-garbage).
function impl.ComponentExists(ped, compId, collection, drawable)
    if collection and collection ~= '' then
        local n = GetNumberOfPedCollectionDrawableVariations(ped, compId, collection)
        return drawable < (n or 0)
    end
    return drawable < (GetNumberOfPedDrawableVariations(ped, compId) or 0)
end

KTR.Bridge.Register('clothing', 'natives', 0, impl)
