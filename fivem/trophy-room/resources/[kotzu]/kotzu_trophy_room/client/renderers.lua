--[[
    Display renderer registry (brief §14): every display type plugs in a
    spawner/despawner; streaming.lua is type-agnostic.

    Renderer contract:
        spawn(display, worldTransform) -> handle { entities = {..}, state = {...} } | nil, errCode
        despawn(handle)
]]

KTRC = KTRC or {}
KTRC.Renderers = {}
local R = KTRC.Renderers
local C = KTR.Const

local renderers = {}

function R.Register(displayType, impl)
    renderers[displayType] = impl
end

function R.Get(displayType)
    return renderers[displayType]
end

local function loadModel(nameOrHash, timeoutMs)
    local hash = type(nameOrHash) == 'string' and joaat(nameOrHash) or nameOrHash
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local deadline = GetGameTimer() + (timeoutMs or 8000)
    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then return nil end
        Wait(25)
    end
    return hash
end
R.LoadModel = loadModel

local function spawnPlatform(display, t)
    local platformId = display.platform or 'none'
    for _, p in ipairs(KTR.Config.Platforms) do
        if p.id == platformId and p.model then
            local hash = loadModel(p.model)
            if hash then
                local obj = CreateObject(hash, t.x, t.y, t.z - 1.0, false, false, false)
                SetModelAsNoLongerNeeded(hash)
                PlaceObjectOnGroundProperly(obj)
                FreezeEntityPosition(obj, true)
                return obj
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------- mannequin

R.Register(C.DisplayType.MANNEQUIN, {
    spawn = function(display, t)
        local model = C.Model[display.gender or C.Gender.MALE]
        local hash = loadModel(model)
        if not hash then return nil, C.Err.INTERNAL end
        local ped = CreatePed(4, hash, t.x, t.y, t.z, t.heading, false, false)
        SetModelAsNoLongerNeeded(hash)
        if not DoesEntityExist(ped) then return nil, C.Err.INTERNAL end

        local ok, errCode, blockers = KTRC.Mannequin.ApplyOutfit(ped, display.gender, display.outfit)
        -- On refusal the ped is already in safe base plastic (or bare freemode if
        -- even the manifest is missing — in that case despawn it outright).
        local state = { outfitError = nil }
        if not ok then
            state.outfitError = errCode
            state.blockers = blockers
            if errCode == C.Err.MANIFEST_NOT_BUILT then
                DeleteEntity(ped)
                print(('[kotzu_trophy] display %s refused: %s'):format(display.uid, errCode))
                return nil, errCode
            end
            print(('[kotzu_trophy] display %s outfit refused: %s (%d blocker(s)) — base plastic shown')
                :format(display.uid, errCode, #(blockers or {})))
        end

        KTRC.Mannequin.Harden(ped, KTR.Config.Streaming.Collision)
        SetEntityCoordsNoOffset(ped, t.x, t.y, t.z, false, false, false)
        SetEntityHeading(ped, t.heading)
        KTRC.Poses.Apply(ped, display.poseId)

        local entities = { ped }
        local platform = spawnPlatform(display, t)
        if platform then entities[#entities + 1] = platform end
        return { entities = entities, ped = ped, state = state }
    end,
    despawn = function(handle)
        for _, e in ipairs(handle.entities) do
            if DoesEntityExist(e) then DeleteEntity(e) end
        end
    end,
})

-- ------------------------------------------------------------------ weapons

local function spawnWeaponObject(display, t, zOffset)
    local meta = display.item and display.item.metadata or {}
    local weaponHash = joaat(display.item.name)
    if not IsWeaponValid(weaponHash) then return nil end
    RequestWeaponAsset(weaponHash, 31, 0)
    local deadline = GetGameTimer() + 8000
    while not HasWeaponAssetLoaded(weaponHash) do
        if GetGameTimer() > deadline then return nil end
        Wait(25)
    end
    local obj = CreateWeaponObject(weaponHash, 0, t.x, t.y, t.z + (zOffset or 1.0), true, 1.0, 0)
    if not DoesEntityExist(obj) then return nil end
    if meta.tint then SetWeaponObjectTintIndex(obj, tonumber(meta.tint) or 0) end
    if type(meta.components) == 'table' then
        for _, compName in ipairs(meta.components) do
            local compHash = joaat(compName)
            if DoesWeaponTakeWeaponComponent(weaponHash, compHash) then
                GiveWeaponComponentToWeaponObject(obj, compHash)
            end
        end
    end
    SetEntityHeading(obj, t.heading)
    FreezeEntityPosition(obj, true)
    return obj
end

local function caseStyleFor(display)
    local styles = KTR.Config.Weapons.CaseStyles
    return styles[display.caseStyle] or styles[KTR.Config.Weapons.DefaultCaseStyle]
end

local function weaponRenderer(kind)
    return {
        spawn = function(display, t)
            local entities = {}
            local zOff = 0.0
            if kind == 'case' then
                local style = caseStyleFor(display)
                zOff = style.itemZ
                local hash = loadModel(style.model)
                if hash then
                    local case = CreateObject(hash, t.x, t.y, t.z, false, false, false)
                    SetModelAsNoLongerNeeded(hash)
                    SetEntityHeading(case, t.heading)
                    FreezeEntityPosition(case, true)
                    entities[#entities + 1] = case
                end
            elseif kind == 'stand' then
                zOff = 1.1
                local hash = loadModel(KTR.Config.Weapons.StandModel)
                if hash then
                    local stand = CreateObject(hash, t.x, t.y, t.z, false, false, false)
                    SetModelAsNoLongerNeeded(hash)
                    SetEntityHeading(stand, t.heading)
                    FreezeEntityPosition(stand, true)
                    entities[#entities + 1] = stand
                end
            end
            local weapon = spawnWeaponObject(display, t, zOff)
            if not weapon then
                for _, e in ipairs(entities) do DeleteEntity(e) end
                return nil, C.Err.INTERNAL
            end
            entities[#entities + 1] = weapon

            -- showcase auto-rotate (cases and stands; never wall mounts)
            local rotate = display.settings and display.settings.rotate
            if kind ~= 'wall' and rotate and rotate.enabled then
                KTRC.Rotator.Add(weapon, rotate.speed)
            end
            return { entities = entities, weapon = weapon, state = {} }
        end,
        despawn = function(handle)
            if handle.weapon then KTRC.Rotator.Remove(handle.weapon) end
            for _, e in ipairs(handle.entities) do
                if DoesEntityExist(e) then DeleteEntity(e) end
            end
        end,
    }
end

R.Register(C.DisplayType.WEAPON_WALL, weaponRenderer('wall'))
R.Register(C.DisplayType.WEAPON_STAND, weaponRenderer('stand'))
R.Register(C.DisplayType.WEAPON_CASE, weaponRenderer('case'))

-- ------------------------------------------------------- rare item / trophy

local function propRenderer(defaultModel)
    return {
        spawn = function(display, t)
            local meta = display.item and display.item.metadata or {}
            local model = meta.model or defaultModel
            local hash = loadModel(model)
            if not hash then return nil, C.Err.INTERNAL end
            local obj = CreateObject(hash, t.x, t.y, t.z, false, false, false)
            SetModelAsNoLongerNeeded(hash)
            if not DoesEntityExist(obj) then return nil, C.Err.INTERNAL end
            SetEntityHeading(obj, t.heading)
            FreezeEntityPosition(obj, true)
            return { entities = { obj }, state = {} }
        end,
        despawn = function(handle)
            for _, e in ipairs(handle.entities) do
                if DoesEntityExist(e) then DeleteEntity(e) end
            end
        end,
    }
end

R.Register(C.DisplayType.RARE_ITEM, propRenderer('prop_drug_package_02'))
R.Register(C.DisplayType.ACHIEVEMENT, propRenderer('prop_trophy_gold'))
