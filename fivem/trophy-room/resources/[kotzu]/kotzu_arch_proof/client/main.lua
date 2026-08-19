--[[
    kotzu_arch_proof — client test runner
    Executes ADR-001 proof tests A1/A2, B1..B6, C1, N1 and submits a structured
    result set to the server, which persists arch_proof_results.json.

    Usage (in-game):
        /archproof run       run the full suite
        /archproof cleanup   delete any leftover test peds
]]

local results = {}
local testPeds = {}

local function say(msg)
    print(('[archproof] %s'):format(msg))
    TriggerEvent('chat:addMessage', { color = { 255, 190, 60 }, args = { 'archproof', msg } })
end

local function record(id, status, detail)
    results[#results + 1] = {
        id = id,
        status = status, -- PASS | FAIL | SKIPPED | NOT_YET_STREAMED | INFO
        detail = detail or '',
        at = GetGameTimer(),
    }
    say(('%s: %s — %s'):format(id, status, detail or ''))
end

local function screenshotCheckpoint(id, what)
    say(('SCREENSHOT CHECKPOINT [%s]: %s — capture now (F8 `screenshot` or your tool), then continue.'):format(id, what))
    record(id .. '.screenshot', 'INFO', 'operator screenshot requested: ' .. what)
    Wait(8000)
end

local function loadModel(name, timeoutMs)
    local hash = joaat(name)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then
        return nil, 'model not in CD image / invalid'
    end
    RequestModel(hash)
    local deadline = GetGameTimer() + (timeoutMs or 10000)
    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then
            return nil, 'model load timeout'
        end
        Wait(50)
    end
    return hash
end

local function spawnTestPed(modelName, offsetMul)
    local hash, err = loadModel(modelName)
    if not hash then return nil, err end
    local p = GetEntityCoords(PlayerPedId())
    local off = ArchProofConfig.SpawnOffset * (offsetMul or 1.0)
    local ped = CreatePed(4, hash, p.x + off.x, p.y + off.y, p.z, 0.0, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(ped) then return nil, 'CreatePed returned invalid entity' end
    testPeds[#testPeds + 1] = ped
    return ped
end

local function hardenPed(ped)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCanBeTargetted(ped, false)
    SetEntityProofs(ped, true, true, true, true, true, true, true, true)
end

local function cleanup()
    for _, ped in ipairs(testPeds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    testPeds = {}
end

local function listCollections(ped)
    local names = {}
    local ok, count = pcall(GetPedCollectionsCount, ped)
    if not ok then return nil, 'GetPedCollectionsCount unavailable: ' .. tostring(count) end
    for i = 0, count - 1 do
        local okName, name = pcall(GetPedCollectionName, ped, i)
        names[#names + 1] = okName and name or ('<error@%d>'):format(i)
    end
    return names, count
end

-- ---------------------------------------------------------------- Candidate A

local function testCandidateA()
    local hash = joaat(ArchProofConfig.CandidateAModel)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then
        record('A1', 'SKIPPED', ('addon test model "%s" not installed; Candidate A falls back to documented constraints E1/E2'):format(ArchProofConfig.CandidateAModel))
        record('A2', 'SKIPPED', 'no addon ped available to probe freemode collections against')
        return
    end
    local ped, err = spawnTestPed(ArchProofConfig.CandidateAModel)
    if not ped then
        record('A1', 'FAIL', 'model exists but spawn failed: ' .. tostring(err))
        return
    end
    record('A1', 'PASS', 'addon test ped spawned')
    hardenPed(ped)

    -- Probe: does the addon ped expose the freemode/default clothing collections?
    local names = listCollections(ped)
    local nDefault = 0
    local okN, n = pcall(GetNumberOfPedCollectionDrawableVariations, ped, 11, '')
    if okN then nDefault = n end
    local detail = ('collections=[%s]; base-collection jbib drawables=%d')
        :format(names and table.concat(names, ',') or 'n/a', nDefault)
    -- Candidate A is viable only if it sees a real clothing library without duplication.
    if nDefault and nDefault > 1 then
        record('A2', 'PASS', 'UNEXPECTED: addon ped exposes a populated clothing library — re-evaluate ADR-001. ' .. detail)
    else
        record('A2', 'FAIL', 'addon ped does not expose freemode clothing library (expected per E1/E2). ' .. detail)
    end
end

-- ------------------------------------------------------------- Candidate B/C

local function testFreemode(gender, modelName)
    local tag = ('B[%s]'):format(gender)
    local ped, err = spawnTestPed(modelName, gender == 'male' and 1.0 or 1.8)
    if not ped then
        record(tag .. '.spawn', 'FAIL', tostring(err))
        return nil
    end
    hardenPed(ped)

    -- B1: collection enumeration
    local names, countOrErr = listCollections(ped)
    if names then
        record('B1.' .. gender, 'PASS', ('%d collections: %s'):format(countOrErr, table.concat(names, ',')))
    else
        record('B1.' .. gender, 'FAIL', tostring(countOrErr))
    end

    -- B2: collection-addressed dressing round-trip against the base collection
    local comp = 11 -- jbib/top
    local okSet = pcall(SetPedCollectionComponentVariation, ped, comp, '', 0, 0, 0)
    local gotColl = GetPedDrawableVariationCollectionName(ped, comp)
    local gotIdx = GetPedDrawableVariationCollectionLocalIndex(ped, comp)
    if okSet and gotIdx == 0 then
        record('B2.' .. gender, 'PASS', ('set ("",0) -> read ("%s",%d)'):format(tostring(gotColl), gotIdx))
    else
        record('B2.' .. gender, 'FAIL', ('set ok=%s read=("%s",%s)'):format(tostring(okSet), tostring(gotColl), tostring(gotIdx)))
    end

    -- B3/C1: mannequin collection availability per skin component
    local coll = ArchProofConfig.MannequinCollection
    local missing, present = {}, {}
    for _, c in ipairs(ArchProofConfig.SkinComponents) do
        local okC, nC = pcall(GetNumberOfPedCollectionDrawableVariations, ped, c, coll)
        if okC and nC and nC > 0 then
            present[#present + 1] = ('%d:%d'):format(c, nC)
        else
            missing[#missing + 1] = tostring(c)
        end
    end
    if #missing == 0 then
        record('B3.' .. gender, 'PASS', 'mannequin drawables present for components ' .. table.concat(present, ','))
        -- apply them
        for _, c in ipairs(ArchProofConfig.SkinComponents) do
            SetPedCollectionComponentVariation(ped, c, coll, 0, 0, 0)
        end
        screenshotCheckpoint('B4.' .. gender, 'mannequin body components applied — verify zero human skin')
        local okC1, nC1 = pcall(GetNumberOfPedCollectionDrawableVariations, ped, 11, coll)
        if okC1 and nC1 and nC1 > 0 then
            SetPedCollectionComponentVariation(ped, 11, coll, 0, 0, 0)
            local rColl = GetPedDrawableVariationCollectionName(ped, 11)
            record('C1.' .. gender, rColl == coll and 'PASS' or 'FAIL',
                ('converted-garment slot applied; read back collection "%s"'):format(tostring(rColl)))
        else
            record('C1.' .. gender, 'NOT_YET_STREAMED', 'no converted garments in mannequin collection yet')
        end
    else
        record('B3.' .. gender, 'NOT_YET_STREAMED',
            ('mannequin collection missing for components [%s] — build kotzu_mannequin_assets first'):format(table.concat(missing, ',')))
        record('C1.' .. gender, 'NOT_YET_STREAMED', 'depends on B3')
    end

    -- B5: neutral head blend + overlay clear
    SetPedHeadBlendData(ped, 0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0, false)
    for i = 0, 12 do
        SetPedHeadOverlay(ped, i, 255, 0.0)
    end
    Wait(250)
    local overlaysClear = true
    for i = 0, 12 do
        local _, overlayValue = GetPedHeadOverlayData(ped, i)
        if overlayValue ~= 255 then overlaysClear = false end
    end
    record('B5.' .. gender, overlaysClear and 'PASS' or 'FAIL',
        overlaysClear and 'all head overlays read back 255' or 'an overlay did not clear')
    screenshotCheckpoint('B5.' .. gender, 'head close-up — verify no facial overlays/features beyond mesh')

    return ped
end

local function testStability(ped, gender)
    if not ped or not DoesEntityExist(ped) then
        record('B6.' .. gender, 'SKIPPED', 'no ped from earlier steps')
        return
    end
    local p0 = GetEntityCoords(ped)
    local h0 = GetEntityHeading(ped)
    local hp0 = GetEntityHealth(ped)
    ApplyDamageToPed(ped, 50, false)
    local soak = ArchProofConfig.QuickMode and 5000 or ArchProofConfig.StabilitySoakMs
    say(('B6.%s soaking %ds…'):format(gender, soak // 1000))
    Wait(soak)
    local p1 = GetEntityCoords(ped)
    local moved = #(p1 - p0)
    local h1 = GetEntityHeading(ped)
    local hp1 = GetEntityHealth(ped)
    local ok = moved < 0.01 and math.abs(h1 - h0) < 0.1 and hp1 >= hp0
    record('B6.' .. gender, ok and 'PASS' or 'FAIL',
        ('moved=%.4f dHeading=%.2f hp %d->%d'):format(moved, math.abs(h1 - h0), hp0, hp1))
end

-- ---------------------------------------------------------------------- N1

local function testNetworkedComparison()
    local t0 = GetGameTimer()
    local localPed = spawnTestPed(ArchProofConfig.MaleModel, 2.6)
    local tLocal = GetGameTimer() - t0
    if localPed then hardenPed(localPed) end

    t0 = GetGameTimer()
    local hash = loadModel(ArchProofConfig.MaleModel)
    local netPed
    if hash then
        local p = GetEntityCoords(PlayerPedId())
        netPed = CreatePed(4, hash, p.x - 2.0, p.y - 2.0, p.z, 0.0, true, true)
        if DoesEntityExist(netPed) then testPeds[#testPeds + 1] = netPed end
    end
    local tNet = GetGameTimer() - t0
    local netId = netPed and DoesEntityExist(netPed) and NetworkGetNetworkIdFromEntity(netPed) or -1
    record('N1', 'INFO', ('local spawn %dms; networked spawn %dms (netId=%d). Local peds selected per E7; MP determinism covered by acceptance tests T10/T13.'):format(tLocal, tNet, netId))
end

-- --------------------------------------------------------------------- main

local running = false

local function runSuite()
    if running then say('suite already running') return end
    running = true
    results = {}
    say('starting ADR-001 proof suite — stay still, keep the area clear')

    testCandidateA()
    local malePed = testFreemode('male', ArchProofConfig.MaleModel)
    local femalePed = testFreemode('female', ArchProofConfig.FemaleModel)
    testStability(malePed, 'male')
    testStability(femalePed, 'female')
    testNetworkedComparison()

    local meta = {
        gameBuild = GetGameBuildNumber and GetGameBuildNumber() or -1,
        gameName = GetGameName and GetGameName() or 'unknown',
        finishedAt = GetGameTimer(),
    }
    TriggerServerEvent('kotzu_arch_proof:submit', results, meta)
    say('suite complete — results submitted; server writes arch_proof_results.json')
    cleanup()
    running = false
end

RegisterCommand('archproof', function(_, args)
    local sub = args[1]
    if sub == 'run' then
        CreateThread(runSuite)
    elseif sub == 'cleanup' then
        cleanup()
        say('test peds removed')
    else
        say('usage: /archproof run | /archproof cleanup')
    end
end, false)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then cleanup() end
end)
