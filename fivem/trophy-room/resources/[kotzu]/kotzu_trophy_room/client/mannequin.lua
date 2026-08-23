--[[
    Mannequin dressing (ADR-001 Candidate B+C, client side).

    Invariant: NO HUMAN SKIN, EVER. If anything cannot be resolved to a
    skin-free representation, the mannequin stays in base plastic and the
    caller receives OUTFIT_INCOMPATIBLE with the exact blockers. There is no
    human-skinned fallback path in this file by construction.
]]

KTRC = KTRC or {}
KTRC.Mannequin = {}
local MQ = KTRC.Mannequin
local C = KTR.Const
local M = KTRC.Manifest

local function applyCollectionComp(ped, compId, collection, drawable, texture, palette)
    if collection and collection ~= '' then
        SetPedCollectionComponentVariation(ped, compId, collection, drawable, texture or 0, palette or 0)
    else
        SetPedComponentVariation(ped, compId, drawable, texture or 0, palette or 0)
    end
end

---Strip the ped to base mannequin plastic: neutral blend, no overlays,
---mannequin body drawables on all skin components, everything else hidden.
---@return boolean ok, string|nil errCode
function MQ.ApplyBase(ped, gender)
    if not M.Built() then return false, C.Err.MANIFEST_NOT_BUILT end
    local coll = C.MANNEQUIN_COLLECTION

    SetPedHeadBlendData(ped, 0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0, false)
    for i = 0, 12 do SetPedHeadOverlay(ped, i, 255, 0.0) end
    ClearPedDecorations(ped)
    ClearAllPedProps(ped)

    for _, compId in ipairs(C.BodyComponents) do
        if compId == C.Comp.TEEF then
            SetPedComponentVariation(ped, compId, 0, 0, 0) -- hidden by faceless head
        else
            local idx = M.BodyDrawable(gender, compId, '', 0)
            if idx == nil then return false, C.Err.MANIFEST_NOT_BUILT end
            applyCollectionComp(ped, compId, coll, idx, 0, 0)
        end
    end
    -- garment slots start naked-safe: lowr/feet get the designated mannequin
    -- base pieces; if the manifest lacks them the whole spawn is refused —
    -- engine-default legs/feet (human skin) must never be shown
    for _, compId in ipairs({ C.Comp.LOWR, C.Comp.FEET }) do
        local idx = M.BodyDrawable(gender, compId, '', 0)
        if idx == nil then return false, C.Err.MANIFEST_NOT_BUILT end
        applyCollectionComp(ped, compId, coll, idx, 0, 0)
    end
    for _, compId in ipairs({ C.Comp.BERD, C.Comp.ACCS, C.Comp.TASK, C.Comp.DECL, C.Comp.JBIB }) do
        SetPedComponentVariation(ped, compId, 0, 0, 0)
    end
    return true
end

---Dress a mannequin ped with a normalized outfit through the manifest.
---@return boolean ok, string|nil errCode, table blockers
function MQ.ApplyOutfit(ped, gender, outfit)
    local okBase, errBase = MQ.ApplyBase(ped, gender)
    if not okBase then return false, errBase, {} end
    if outfit == nil then return true, nil, {} end

    local okV = KTR.Schemas.ValidateOutfit(outfit)
    if not okV or outfit.gender ~= gender then
        return false, C.Err.OUTFIT_INVALID, {}
    end

    -- First pass: decide every garment before touching the ped, so an
    -- incompatible outfit never half-applies.
    local plan, blockers = {}, {}
    local bodySet = {}
    for _, b in ipairs(C.BodyComponents) do bodySet[b] = true end

    for compKey, comp in pairs(outfit.components) do
        local compId = tonumber(compKey)
        if bodySet[compId] then
            -- base skin slots: mannequin body variant matched to the original cut
            local idx = M.BodyDrawable(gender, compId, comp.collection, comp.drawable)
            if compId == C.Comp.TEEF then
                plan[#plan + 1] = { compId = compId, collection = '', drawable = 0, texture = 0 }
            elseif idx == nil then
                blockers[#blockers + 1] = {
                    compId = compId, status = 'body_variant_missing',
                    collection = comp.collection, drawable = comp.drawable,
                }
            else
                plan[#plan + 1] = { compId = compId, collection = C.MANNEQUIN_COLLECTION,
                                    drawable = idx, texture = 0 }
            end
        else
            local status, converted = M.GarmentStatus(gender, compId, comp.collection, comp.drawable)
            if status == C.GarmentStatus.SKIN_FREE then
                plan[#plan + 1] = { compId = compId, collection = comp.collection,
                                    drawable = comp.drawable, texture = comp.texture,
                                    palette = comp.palette }
            elseif status == C.GarmentStatus.CONVERTED and converted then
                plan[#plan + 1] = { compId = compId, collection = converted.collection,
                                    drawable = converted.drawable, texture = comp.texture }
            else
                blockers[#blockers + 1] = {
                    compId = compId, status = status,
                    collection = comp.collection, drawable = comp.drawable,
                }
            end
        end
    end

    if #blockers > 0 then
        -- explicit refusal: mannequin remains base plastic (already applied)
        return false, C.Err.OUTFIT_INCOMPATIBLE, blockers
    end

    for _, step in ipairs(plan) do
        applyCollectionComp(ped, step.compId, step.collection, step.drawable,
            step.texture, step.palette)
    end

    -- props: pass through (manifest prop exceptions could block here later)
    for propKey, prop in pairs(outfit.props or {}) do
        local propId = tonumber(propKey)
        if prop.cleared then
            ClearPedProp(ped, propId)
        elseif prop.collection and prop.collection ~= '' then
            SetPedCollectionPropIndex(ped, propId, prop.collection, prop.drawable, prop.texture, true)
        else
            SetPedPropIndex(ped, propId, prop.drawable, prop.texture, true)
        end
    end
    return true, nil, {}
end

---Make the ped a statue: frozen, invincible, non-reactive (brief §9).
function MQ.Harden(ped, collision)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, false)
    SetPedCanBeTargetted(ped, false)
    SetPedCanBeDraggedOut(ped, false)
    SetPedConfigFlag(ped, 185, true)  -- disable melee reactions
    SetPedConfigFlag(ped, 108, true)  -- don't react to explosions
    SetEntityProofs(ped, true, true, true, true, true, true, true, true)
    SetPedDiesWhenInjured(ped, false)
    StopPedSpeaking(ped, true)
    DisablePedPainAudio(ped, true)
    if collision == false then
        SetEntityCollision(ped, false, false)
    end
end
