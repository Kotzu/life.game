--[[ NUI glue (brief §17): dark trophy-room UI, minimal messaging surface. ]]

KTRC = KTRC or {}
KTRC.UI = {}
KTR.UI = KTRC.UI -- alias used by the fallback target bridge
local UI = KTRC.UI
local C = KTR.Const

local open = false
local optionMenuCtx = nil

local function post(action, data)
    if action == 'open' and data then
        data.strings = KTR.UIStrings()
    end
    SendNUIMessage({ action = action, data = data })
end

local function setOpen(state)
    open = state
    SetNuiFocus(state, state)
end

function UI.Close()
    post('close')
    setOpen(false)
end

---Placement wizard: display type -> (mannequin: gender/outfit/pose/platform)
function UI.OpenWizard()
    local clothingBridge = KTR.Bridge.Get('clothing')
    local saved = nil
    if clothingBridge and clothingBridge.GetSavedOutfits then
        saved = clothingBridge.GetSavedOutfits()
    end
    local bridges = KTR.RPC.Call('bridges:describe') or {}
    local caseStyles = {}
    for id in pairs(KTR.Config.Weapons.CaseStyles) do
        caseStyles[#caseStyles + 1] = { id = id }
    end
    table.sort(caseStyles, function(a, b) return a.id < b.id end)
    post('open', {
        screen = 'wizard',
        poses = KTRC.Poses.List(KTR.Config.Debug),
        platforms = KTR.Config.Platforms,
        caseStyles = caseStyles,
        defaultCaseStyle = KTR.Config.Weapons.DefaultCaseStyle,
        manifestBuilt = KTRC.Manifest.Built(),
        manifestVersion = KTRC.Manifest.Version(),
        savedOutfits = saved,
        inventoryFunctional = bridges.inventoryFunctional == true,
        playerGender = KTR.Bridge.Get('framework').GetGender(),
    })
    setOpen(true)
end

function UI.ShowDetails(display, lines)
    post('open', { screen = 'details', display = {
        uid = display.uid, label = display.label, description = display.description,
        displayType = display.displayType, gender = display.gender,
        poseId = display.poseId, platform = display.platform,
        item = display.item,
    }, lines = lines })
    setOpen(true)
end

function UI.OpenPoseMenu(display)
    post('open', { screen = 'poses', uid = display.uid,
                   current = display.poseId, poses = KTRC.Poses.List(KTR.Config.Debug) })
    setOpen(true)
end

function UI.OpenRotateMenu(display)
    local cfg = KTR.Config.Display
    local rotate = (display.settings and display.settings.rotate) or {}
    post('open', { screen = 'rotate', uid = display.uid,
                   enabled = rotate.enabled == true,
                   speed = rotate.speed or cfg.DefaultRotateSpeed,
                   minSpeed = cfg.MinRotateSpeed, maxSpeed = cfg.MaxRotateSpeed })
    setOpen(true)
end

function UI.ConfirmRemove(display)
    post('open', { screen = 'confirmRemove', uid = display.uid,
                   label = display.label or display.uid:sub(1, 8) })
    setOpen(true)
end

function UI.OpenOptionMenu(options, entity)
    optionMenuCtx = { options = options, entity = entity }
    local labels = {}
    for i, o in ipairs(options) do labels[i] = o.label end
    post('open', { screen = 'options', options = labels })
    setOpen(true)
end

-- ------------------------------------------------------------ NUI callbacks

RegisterNUICallback('ktr:close', function(_, cb)
    setOpen(false)
    cb({ ok = true })
end)

RegisterNUICallback('ktr:optionSelected', function(data, cb)
    setOpen(false)
    cb({ ok = true })
    local ctx = optionMenuCtx
    optionMenuCtx = nil
    if ctx and ctx.options[data.index] then
        ctx.options[data.index].action(ctx.entity)
    end
end)

RegisterNUICallback('ktr:placeMannequin', function(data, cb)
    setOpen(false)
    cb({ ok = true })
    CreateThread(function()
        local gender = data.gender == 'female' and C.Gender.FEMALE or C.Gender.MALE
        local outfit = nil
        local cbridge = KTR.Bridge.Get('clothing')
        if data.outfitSource == 'current' then
            local captured, err = cbridge.Capture(PlayerPedId())
            if not captured or captured.gender ~= gender then
                KTR.Bridge.Get('framework').Notify(KTR.ErrText(C.Err.OUTFIT_INVALID), 'error')
                return
            end
            outfit = captured
        elseif data.outfitSource == 'saved' then
            -- No silent substitution: a chosen-saved-outfit flow either applies
            -- exactly that outfit or aborts with a visible error.
            if not data.savedId then
                KTR.Bridge.Get('framework').Notify(KTR.ErrText(C.Err.BAD_INPUT), 'error')
                return
            end
            if not cbridge.GetSavedOutfit then
                KTR.Bridge.Get('framework').Notify(
                    KTR.ErrText(C.Err.OUTFIT_INVALID) .. ' (saved outfits unsupported by the installed clothing system)', 'error')
                return
            end
            local saved, err = cbridge.GetSavedOutfit(tonumber(data.savedId) or data.savedId, gender)
            if not saved then
                KTR.Bridge.Get('framework').Notify(
                    KTR.ErrText(err or C.Err.OUTFIT_INVALID), 'error')
                return
            end
            outfit = saved
        end
        local draft = {
            displayType = C.DisplayType.MANNEQUIN,
            gender = gender,
            outfit = outfit,
            poseId = data.poseId,
            platform = data.platform,
            label = data.label and data.label:sub(1, KTR.Config.Limits.LabelLength) or nil,
        }
        KTRC.Placement.PlaceAndSave(draft)
    end)
end)

RegisterNUICallback('ktr:placeWeapon', function(data, cb)
    setOpen(false)
    cb({ ok = true })
    CreateThread(function()
        local kind = data.kind
        local dtype = (kind == 'wall' and C.DisplayType.WEAPON_WALL)
            or (kind == 'case' and C.DisplayType.WEAPON_CASE)
            or C.DisplayType.WEAPON_STAND
        local caseStyle = nil
        if kind == 'case' and KTR.Config.Weapons.CaseStyles[data.caseStyle] then
            caseStyle = data.caseStyle
        end
        local draft = {
            displayType = dtype,
            caseStyle = caseStyle,
            item = { name = tostring(data.itemName or ''):lower():sub(1, 64), metadata = {} },
            label = data.label and data.label:sub(1, KTR.Config.Limits.LabelLength) or nil,
        }
        local idKey = ('place_%d_%d'):format(GetGameTimer(), math.random(1000, 9999))
        KTRC.Placement.PlaceAndSave(draft, idKey)
    end)
end)

RegisterNUICallback('ktr:setPose', function(data, cb)
    setOpen(false)
    cb({ ok = true })
    CreateThread(function()
        local res, err = KTR.RPC.Call('displays:update',
            { uid = data.uid, patch = { poseId = data.poseId } })
        local fw = KTR.Bridge.Get('framework')
        if not res then fw.Notify(KTR.ErrText(err), 'error')
        else fw.Notify(KTR.L('updated'), 'success') end
    end)
end)

RegisterNUICallback('ktr:rename', function(data, cb)
    setOpen(false)
    cb({ ok = true })
    CreateThread(function()
        local res, err = KTR.RPC.Call('displays:update', { uid = data.uid, patch = {
            label = tostring(data.label or ''):sub(1, KTR.Config.Limits.LabelLength),
            description = tostring(data.description or ''):sub(1, KTR.Config.Limits.DescriptionLength),
        } })
        local fw = KTR.Bridge.Get('framework')
        if not res then fw.Notify(KTR.ErrText(err), 'error')
        else fw.Notify(KTR.L('updated'), 'success') end
    end)
end)

RegisterNUICallback('ktr:setRotate', function(data, cb)
    setOpen(false)
    cb({ ok = true })
    CreateThread(function()
        local cfg = KTR.Config.Display
        local speed = math.max(cfg.MinRotateSpeed,
            math.min(cfg.MaxRotateSpeed, tonumber(data.speed) or cfg.DefaultRotateSpeed))
        local res, err = KTR.RPC.Call('displays:update', { uid = data.uid, patch = {
            settings = { rotate = { enabled = data.enabled == true, speed = speed } },
        } })
        local fw = KTR.Bridge.Get('framework')
        if not res then fw.Notify(KTR.ErrText(err), 'error')
        else fw.Notify(KTR.L('updated'), 'success') end
    end)
end)

RegisterNUICallback('ktr:confirmRemove', function(data, cb)
    setOpen(false)
    cb({ ok = true })
    CreateThread(function()
        local res, err = KTR.RPC.Call('displays:delete', { uid = data.uid })
        local fw = KTR.Bridge.Get('framework')
        if not res then fw.Notify(KTR.ErrText(err), 'error')
        else fw.Notify(KTR.L('removed'), 'success') end
    end)
end)
