--[[
    Placement mode (brief §11): ghost preview, translate/rotate/ground-align/
    wall-align/fine/snap, collision preview, camera-relative movement.
    The per-frame loop exists ONLY while placement is active. Nothing is
    persisted until the server validates and saves (displays:place/update).
]]

KTRC = KTRC or {}
KTRC.Placement = {}
local PL = KTRC.Placement
local C = KTR.Const

local active = false

local function ghostify(handle, collisionPreview)
    for _, e in ipairs(handle.entities) do
        SetEntityAlpha(e, 180, false)
        SetEntityCollision(e, collisionPreview == true, false)
        FreezeEntityPosition(e, true)
    end
end

local function setGhostTransform(handle, t)
    for i, e in ipairs(handle.entities) do
        if i == 1 then
            SetEntityCoordsNoOffset(e, t.x, t.y, t.z, false, false, false)
            SetEntityHeading(e, t.heading)
        end
    end
end

local function groundAlign(t)
    local found, gz = GetGroundZFor_3dCoord(t.x, t.y, t.z + 1.5, false)
    if found then t.z = gz end
    return t
end

local function wallAlign(t)
    local probe = KTR.Config.Weapons.WallOffsetProbe
    local heading = math.rad(t.heading)
    local dx, dy = -math.sin(heading), math.cos(heading)
    local ray = StartShapeTestRay(t.x, t.y, t.z + 1.2,
        t.x + dx * probe, t.y + dy * probe, t.z + 1.2, 1, PlayerPedId(), 0)
    local _, hit, endCoords, surfaceNormal = GetShapeTestResult(ray)
    if hit == 1 then
        t.x = endCoords.x - surfaceNormal.x * 0.05
        t.y = endCoords.y - surfaceNormal.y * 0.05
        t.heading = (math.deg(math.atan(surfaceNormal.y, surfaceNormal.x)) - 90.0) % 360.0
        return t, true
    end
    return t, false
end

local function snap(v, inc)
    if inc <= 0.0 then return v end
    return math.floor(v / inc + 0.5) * inc
end

local function drawBounds(handle, t, colliding)
    local r, g, b = 90, 200, 255
    if colliding then r, g, b = 255, 90, 90 end
    DrawMarker(1, t.x, t.y, t.z - 0.02, 0, 0, 0, 0, 0, 0,
        0.9, 0.9, 0.35, r, g, b, 110, false, false, 2, false, nil, nil, false)
end

local function help(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

---Run interactive placement for a draft display.
---@param draft table display payload WITHOUT transform/scope (caller-built)
---@param startTransform table|nil initial transform (move mode)
---@return table|nil transform confirmed, plus scope fields merged into draft
function PL.Run(draft, startTransform)
    if active then return nil end
    active = true

    local housing = KTR.Bridge.Get('housing')
    local room = housing and housing.CurrentRoom and housing.CurrentRoom()

    local ppos = GetEntityCoords(PlayerPedId())
    local fwdHeading = GetEntityHeading(PlayerPedId())
    local t = startTransform and {
        x = startTransform.x, y = startTransform.y, z = startTransform.z,
        heading = startTransform.heading,
    } or {
        x = ppos.x - math.sin(math.rad(fwdHeading)) * 2.0,
        y = ppos.y + math.cos(math.rad(fwdHeading)) * 2.0,
        z = ppos.z - 1.0,
        heading = (fwdHeading + 180.0) % 360.0,
    }

    -- ghost via the real renderer so the preview is exactly what will spawn
    local renderer = KTRC.Renderers.Get(draft.displayType)
    if not renderer then active = false return nil end
    local ghostDisplay = {}
    for k, v in pairs(draft) do ghostDisplay[k] = v end
    ghostDisplay.uid = '__ghost__'
    local handle = renderer.spawn(ghostDisplay, t)
    if not handle then
        active = false
        local fw = KTR.Bridge.Get('framework')
        if fw then fw.Notify(KTR.ErrText(C.Err.MANIFEST_NOT_BUILT), 'error') end
        return nil
    end
    local collisionPreview = false
    ghostify(handle, collisionPreview)

    local cfg = KTR.Config.Placement
    local snapIdx = 1
    local confirmed = nil
    local wantWall = cfg.WallAlignTypes[draft.displayType] == true

    while true do
        Wait(0)
        local fine = IsControlPressed(0, 21) -- LSHIFT
        local step = fine and cfg.MoveStepFine or cfg.MoveStep
        local rstep = fine and cfg.RotStepFine or cfg.RotStep

        -- camera-relative planar movement
        local camRotZ = math.rad(GetGameplayCamRot(2).z)
        local fx, fy = -math.sin(camRotZ), math.cos(camRotZ)
        local rx, ry = fy, -fx

        if IsControlPressed(0, 172) then t.x = t.x + fx * step t.y = t.y + fy * step end -- up
        if IsControlPressed(0, 173) then t.x = t.x - fx * step t.y = t.y - fy * step end -- down
        if IsControlPressed(0, 174) then t.x = t.x - rx * step t.y = t.y - ry * step end -- left
        if IsControlPressed(0, 175) then t.x = t.x + rx * step t.y = t.y + ry * step end -- right
        if IsControlPressed(0, 10) then t.z = t.z + step end  -- PageUp
        if IsControlPressed(0, 11) then t.z = t.z - step end  -- PageDown
        if IsControlPressed(0, 44) then t.heading = (t.heading + rstep) % 360.0 end -- Q
        if IsControlPressed(0, 38) then t.heading = (t.heading - rstep) % 360.0 end -- E

        if IsControlJustPressed(0, 47) and KTR.Config.Placement.GroundAlign then -- G
            t = groundAlign(t)
        end
        if IsControlJustPressed(0, 37) then -- TAB: cycle snap
            snapIdx = snapIdx % #cfg.SnapIncrements + 1
        end
        if IsControlJustPressed(0, 73) then -- X: collision preview toggle
            collisionPreview = not collisionPreview
            ghostify(handle, collisionPreview)
        end

        local inc = cfg.SnapIncrements[snapIdx]
        local shown = { x = snap(t.x, inc), y = snap(t.y, inc), z = t.z, heading = t.heading }
        if wantWall then
            local aligned, hit = wallAlign({ x = shown.x, y = shown.y, z = shown.z, heading = shown.heading })
            if hit then shown = aligned end
        end

        -- distance clamp preview
        local dist = #(GetEntityCoords(PlayerPedId()) - vector3(shown.x, shown.y, shown.z))
        local tooFar = dist > cfg.MaxDistance
        setGhostTransform(handle, shown)
        drawBounds(handle, shown, tooFar)
        help(KTR.L('placement_help') .. (' ~s~· snap %.2f'):format(inc))

        if IsControlJustPressed(0, 191) or IsControlJustPressed(0, 201) then -- Enter
            if not tooFar then
                confirmed = shown
                break
            end
        end
        if IsControlJustPressed(0, 177) then break end -- Backspace
    end

    renderer.despawn(handle)
    active = false
    if not confirmed then return nil end

    -- scope resolution: inside a room -> shell/property-relative storage
    if room then
        draft.scopeType = room.scopeType
        draft.scopeId = room.scopeId
        draft.worldTransform = confirmed
        draft.transform = housing.ToLocal(confirmed)
    else
        draft.scopeType = C.ScopeType.WORLD
        draft.scopeId = nil
        draft.transform = confirmed
    end
    return confirmed
end

function PL.IsActive() return active end

---Full flow: run placement then persist via RPC.
---@return string|nil uid, string|nil err
function PL.PlaceAndSave(draft, idKey)
    local confirmed = PL.Run(draft)
    if not confirmed then return nil, 'cancelled' end
    local res, err = KTR.RPC.Call('displays:place', { display = draft, idKey = idKey })
    local fw = KTR.Bridge.Get('framework')
    if not res then
        if fw then fw.Notify(KTR.ErrText(err), 'error') end
        return nil, err
    end
    if fw then fw.Notify(KTR.L('placed'), 'success') end
    return res.uid
end

---Move an existing display (owner path).
function PL.MoveExisting(display)
    local housing = KTR.Bridge.Get('housing')
    local world = display.scopeType == C.ScopeType.WORLD and display.transform
        or (housing and housing.ToWorld(display)) or display.transform
    local draft = {
        displayType = display.displayType, gender = display.gender,
        outfit = display.outfit, poseId = display.poseId, platform = display.platform,
    }
    local confirmed = PL.Run(draft, world)
    if not confirmed then return nil, 'cancelled' end
    local newTransform = draft.transform
    local res, err = KTR.RPC.Call('displays:update',
        { uid = display.uid, patch = { transform = newTransform } })
    local fw = KTR.Bridge.Get('framework')
    if not res then
        if fw then fw.Notify(KTR.ErrText(err), 'error') end
        return nil, err
    end
    if fw then fw.Notify(KTR.L('updated'), 'success') end
    return true
end
