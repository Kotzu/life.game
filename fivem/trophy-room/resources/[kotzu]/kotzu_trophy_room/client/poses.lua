--[[ Pose system (brief §10): anim/scenario poses with fallbacks, re-appliable. ]]

KTRC = KTRC or {}
KTRC.Poses = {}
local P = KTRC.Poses

local byId = {}
for _, pose in ipairs(KTR.Config.Poses) do byId[pose.id] = pose end

function P.Get(id)
    return byId[id or KTR.Config.DefaultPose] or byId[KTR.Config.DefaultPose]
end

function P.List(includeDebug)
    local out = {}
    for _, pose in ipairs(KTR.Config.Poses) do
        if includeDebug or not pose.debugOnly then
            out[#out + 1] = { id = pose.id, label = pose.label }
        end
    end
    return out
end

local function loadDict(dict, timeoutMs)
    if not DoesAnimDictExist(dict) then return false end
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + (timeoutMs or 5000)
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > deadline then return false end
        Wait(25)
    end
    return true
end

local function pedGender(ped)
    if GetEntityModel(ped) == joaat(KTR.Const.Model.female) then
        return KTR.Const.Gender.FEMALE
    end
    return KTR.Const.Gender.MALE
end

---Apply a pose; safe to call again after re-stream (idempotent).
---Resolution order: genderDict[gender] → dict → scenario → fallbackDict →
---fallbackScenario. A gender-specific dict that fails to load falls through
---to the shared dict, so no pose ever silently leaves the ped in a-pose.
---@return boolean ok, string|nil detail
function P.Apply(ped, poseId)
    local pose = P.Get(poseId)
    ClearPedTasksImmediately(ped)

    local dict = pose.dict
    if pose.genderDict then
        dict = pose.genderDict[pedGender(ped)] or pose.dict
    end

    if dict and pose.anim and loadDict(dict) then
        TaskPlayAnim(ped, dict, pose.anim, 4.0, -4.0, -1, pose.flag or 1,
            0.0, false, false, false)
        RemoveAnimDict(dict)
        return true
    end
    -- shared dict as a second try when a gender dict was chosen but missing
    if dict ~= pose.dict and pose.dict and pose.anim and loadDict(pose.dict) then
        TaskPlayAnim(ped, pose.dict, pose.anim, 4.0, -4.0, -1, pose.flag or 1,
            0.0, false, false, false)
        RemoveAnimDict(pose.dict)
        return true, 'shared dict used'
    end
    if pose.scenario then
        TaskStartScenarioInPlace(ped, pose.scenario, 0, true)
        return true, 'scenario used'
    end
    if pose.fallbackDict and pose.fallbackAnim and loadDict(pose.fallbackDict) then
        TaskPlayAnim(ped, pose.fallbackDict, pose.fallbackAnim, 4.0, -4.0, -1,
            pose.flag or 1, 0.0, false, false, false)
        RemoveAnimDict(pose.fallbackDict)
        return true, 'fallback dict used'
    end
    if pose.fallbackScenario then
        TaskStartScenarioInPlace(ped, pose.fallbackScenario, 0, true)
        return true, 'fallback scenario used'
    end
    return false, ('pose %s: no dict/scenario available'):format(pose.id)
end

---Foot-slide guard: scenario/anim application must not move the entity.
---Used by the test harness (acceptance §10).
function P.VerifyStable(ped, poseId, waitMs)
    local before = GetEntityCoords(ped)
    P.Apply(ped, poseId)
    Wait(waitMs or 2000)
    local after = GetEntityCoords(ped)
    return #(after - before) < 0.05, #(after - before)
end
