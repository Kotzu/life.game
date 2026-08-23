--[[
    Client test harness (brief §20). Gated by Config.DevCommands.
    All commands print to F8 console with the [kmq] prefix; screenshot
    checkpoints follow the acceptance runbook numbering.
]]

if not KTR.Config.DevCommands then return end

local C = KTR.Const
local testPed = nil
local testGender = C.Gender.MALE

local function say(msg)
    print('[kmq] ' .. msg)
    TriggerEvent('chat:addMessage', { color = { 120, 200, 255 }, args = { 'kmq', msg } })
end

local function cleanupTestPed()
    if testPed and DoesEntityExist(testPed) then DeleteEntity(testPed) end
    testPed = nil
end

local function spawnTestMannequin(gender, outfit)
    cleanupTestPed()
    local hash = KTRC.Renderers.LoadModel(C.Model[gender])
    if not hash then say('model load failed') return nil end
    local p = GetEntityCoords(PlayerPedId())
    local h = GetEntityHeading(PlayerPedId())
    local x = p.x - math.sin(math.rad(h)) * 2.0
    local y = p.y + math.cos(math.rad(h)) * 2.0
    testPed = CreatePed(4, hash, x, y, p.z, (h + 180.0) % 360.0, false, false)
    SetModelAsNoLongerNeeded(hash)
    testGender = gender
    local ok, err, blockers = KTRC.Mannequin.ApplyOutfit(testPed, gender, outfit)
    KTRC.Mannequin.Harden(testPed, true)
    if ok then
        say(('test mannequin (%s) spawned — outfit ok'):format(gender))
    else
        say(('test mannequin (%s) spawned — outfit refused: %s (%d blockers)')
            :format(gender, tostring(err), #(blockers or {})))
        for _, b in ipairs(blockers or {}) do
            say(('  blocker comp %d %s:%d status=%s'):format(b.compId,
                b.collection or '', b.drawable or -1, b.status))
        end
    end
    return testPed
end

RegisterCommand('kmq:spawn_male', function()
    spawnTestMannequin(C.Gender.MALE)
end, false)

RegisterCommand('kmq:spawn_female', function()
    spawnTestMannequin(C.Gender.FEMALE)
end, false)

RegisterCommand('kmq:spawn_dressed', function()
    local cb = KTR.Bridge.Get('clothing')
    local outfit = cb.Capture(PlayerPedId())
    if not outfit then say('capture failed') return end
    spawnTestMannequin(outfit.gender, outfit)
end, false)

RegisterCommand('kmq:cleanup', cleanupTestPed, false)

-- ----------------------------------------------------- §6 validation matrix

-- Representative outfit matrix. Drawable indexes are base-collection defaults
-- and may shift by game build — adjust per server build, then record results in
-- docs/clothing-compatibility-report.md.
local MATRIX = {
    male = {
        { name = 'full_suit',      comps = { [11] = 4,  [8] = 10, [4] = 10, [6] = 10 } },
        { name = 'police_uniform', comps = { [11] = 55, [8] = 58, [4] = 35, [6] = 25 } },
        { name = 'long_sleeve',    comps = { [11] = 1,  [4] = 0,  [6] = 1 } },
        { name = 'short_sleeve',   comps = { [11] = 26, [4] = 0,  [6] = 1 } },
        { name = 'tank_top',       comps = { [11] = 5,  [4] = 0,  [6] = 1 } },
        { name = 'exposed_torso',  comps = { [11] = 15, [4] = 61, [6] = 34 } },
        { name = 'shorts',         comps = { [11] = 5,  [4] = 12, [6] = 5 } },
        { name = 'sandals',        comps = { [11] = 5,  [4] = 12, [6] = 5 } },
        { name = 'vest_armor',     comps = { [11] = 5,  [9] = 4,  [4] = 0, [6] = 1 } },
        { name = 'bag',            comps = { [11] = 5,  [5] = 44, [4] = 0, [6] = 1 } },
        { name = 'mask',           comps = { [11] = 5,  [1] = 12, [4] = 0, [6] = 1 } },
        { name = 'decals',         comps = { [11] = 5,  [10] = 2, [4] = 0, [6] = 1 } },
    },
    female = {
        { name = 'full_suit',      comps = { [11] = 7,  [8] = 5,  [4] = 24, [6] = 13 } },
        { name = 'police_uniform', comps = { [11] = 48, [8] = 45, [4] = 34, [6] = 24 } },
        { name = 'tank_top',       comps = { [11] = 8,  [4] = 0,  [6] = 1 } },
        { name = 'skirt_dress',    comps = { [11] = 22, [4] = 21, [6] = 3 } },
        { name = 'shorts',         comps = { [11] = 8,  [4] = 12, [6] = 5 } },
        { name = 'sandals',        comps = { [11] = 8,  [4] = 12, [6] = 22 } },
    },
}

local matrixIdx = 0

RegisterCommand('kmq:cycle_outfits', function()
    if not testPed then say('spawn a test mannequin first') return end
    local list = MATRIX[testGender]
    matrixIdx = matrixIdx % #list + 1
    local entry = list[matrixIdx]
    local outfit = {
        schema = C.OUTFIT_SCHEMA, gender = testGender, model = C.Model[testGender],
        components = {}, props = {},
    }
    for comp, drawable in pairs(entry.comps) do
        outfit.components[tostring(comp)] = { collection = '', drawable = drawable,
                                              texture = 0, palette = 0 }
    end
    local ok, err, blockers = KTRC.Mannequin.ApplyOutfit(testPed, testGender, outfit)
    say(('matrix %d/%d "%s": %s'):format(matrixIdx, #list, entry.name,
        ok and 'OK — SCREENSHOT NOW (check for skin!)' or
        ('REFUSED %s (%d blockers)'):format(tostring(err), #(blockers or {}))))
end, false)

RegisterCommand('kmq:cycle_components', function(_, args)
    if not testPed then say('spawn a test mannequin first') return end
    local comp = tonumber(args[1] or 11)
    local n = GetNumberOfPedDrawableVariations(testPed, comp)
    local cur = (tonumber(args[2]) or GetPedDrawableVariation(testPed, comp) + 1) % n
    SetPedComponentVariation(testPed, comp, cur, 0, 0)
    local coll = GetPedDrawableVariationCollectionName(testPed, comp)
    local localIdx = GetPedDrawableVariationCollectionLocalIndex(testPed, comp)
    say(('comp %d -> global %d/%d = (%s, %d)'):format(comp, cur, n, tostring(coll), localIdx))
end, false)

RegisterCommand('kmq:cycle_poses', function()
    if not testPed then say('spawn a test mannequin first') return end
    local poses = KTRC.Poses.List(true)
    local idx = ((tonumber(GetResourceKvpString('kmq_pose_idx') or '0')) % #poses) + 1
    SetResourceKvp('kmq_pose_idx', tostring(idx))
    local stable, moved = KTRC.Poses.VerifyStable(testPed, poses[idx].id, 2000)
    say(('pose %s: %s (moved %.3fm)'):format(poses[idx].id,
        stable and 'stable' or 'FOOT SLIDE / MOVED', moved))
end, false)

RegisterCommand('kmq:show_indexes', function()
    local ped = PlayerPedId()
    for _, comp in ipairs(C.AllComponents) do
        local coll = GetPedDrawableVariationCollectionName(ped, comp)
        local li = GetPedDrawableVariationCollectionLocalIndex(ped, comp)
        local gi = GetPedDrawableVariation(ped, comp)
        say(('comp %2d: global %3d = ("%s", %d) tex %d'):format(comp, gi,
            tostring(coll), li, GetPedTextureVariation(ped, comp)))
    end
end, false)

RegisterCommand('kmq:reload_manifest', function()
    KTRC.Manifest.Load(true)
    local res = KTR.RPC.Call('admin:reloadManifest')
    say(('manifest reloaded: client v%d server v%s'):format(
        KTRC.Manifest.Version(), res and res.version or '?'))
end, false)

RegisterCommand('kmq:refresh', function()
    KTRC.Streaming.RefreshAll()
    say('all displays despawned; scan loop will respawn in range')
end, false)

RegisterCommand('kmq:debug', function()
    local reg, sp = 0, 0
    for _ in pairs(KTRC.Streaming.Registry()) do reg = reg + 1 end
    for uid, h in pairs(KTRC.Streaming.Spawned()) do
        sp = sp + 1
        local d = KTRC.Streaming.Registry()[uid]
        say(('  %s %s ents=%d outfitErr=%s'):format(uid:sub(1, 8),
            d and d.displayType or '?', #h.entities,
            tostring(h.state and h.state.outfitError)))
    end
    say(('registry=%d spawned=%d manifest v%d'):format(reg, sp, KTRC.Manifest.Version()))
end, false)

RegisterCommand('kmq:sim_reconnect', function()
    say('simulating reconnect: despawn all + rebuild from server')
    KTRC.Streaming.DespawnAll()
    KTRC.Streaming.RequestScope()
end, false)

-- Populate the current room with the configured demo layout (acceptance T8).
-- Mannequins place without a captured outfit (base plastic); weapon displays
-- are skipped here (they need a real inventory item + transaction) with a note.
RegisterCommand('kmq:demo_layout', function()
    local layout = KTR.Config.DemoLayout or {}
    local placed, skipped = 0, 0
    for _, d in ipairs(layout) do
        if d.displayType:find('^weapon_') then
            skipped = skipped + 1
        else
            local draft = {
                displayType = d.displayType, gender = d.gender,
                poseId = d.poseId, platform = d.platform, label = d.label,
                scopeType = KTR.Const.ScopeType.WORLD, transform = d.transform,
            }
            local housing = KTR.Bridge.Get('housing')
            local room = housing and housing.CurrentRoom and housing.CurrentRoom()
            if room then
                draft.scopeType = room.scopeType
                draft.scopeId = room.scopeId
            end
            local res = KTR.RPC.Call('displays:place', { display = draft })
            if res then placed = placed + 1 else skipped = skipped + 1 end
        end
    end
    say(('demo layout: %d placed, %d skipped (weapon displays need a real item — use the wizard)'):format(placed, skipped))
end, false)

RegisterCommand('kmq:probe_clothing', function()
    local cb = KTR.Bridge.Get('clothing')
    if cb and cb.Describe then
        say('rcore capabilities: ' .. json.encode(cb.Describe()))
    else
        say('clothing bridge: ' .. (cb and cb.__name or 'none') .. ' (native capture)')
    end
end, false)

-- test shell entry: server sets the bucket, then we teleport + enter the room
RegisterNetEvent('kotzu_trophy:test:enterShell', function(shell)
    local o = shell.origin
    SetEntityCoords(PlayerPedId(), o.x, o.y, o.z, false, false, false, false)
    exports[C.RESOURCE]:EnterRoom({
        scopeType = C.ScopeType.SHELL,
        scopeId = shell.shellId,
        origin = vector4(o.x, o.y, o.z, o.w or 0.0),
        permissions = { owner = true },
    })
    say(('entered test shell %s (bucket %d)'):format(shell.shellId, shell.bucket))
end)

RegisterNetEvent('kotzu_trophy:test:exitShell', function()
    exports[C.RESOURCE]:ExitRoom()
    say('exited test shell')
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then cleanupTestPed() end
end)
