--[[
    Interactions (brief §13): target options per display entity, gated by
    server-side capabilities fetched when the entity streams in.
]]

KTRC = KTRC or {}
KTRC.Interaction = {}
local I = KTRC.Interaction
local C = KTR.Const

local function target() return KTR.Bridge.Get('target') end
local function fw() return KTR.Bridge.Get('framework') end

local function notifyErr(err)
    local f = fw()
    if f then f.Notify(KTR.ErrText(err), 'error') end
end

local function inspect(display, handle)
    local lines = {
        ('%s "%s"'):format(display.displayType, display.label or display.uid:sub(1, 8)),
    }
    if display.description then lines[#lines + 1] = display.description end
    if handle and handle.state and handle.state.outfitError then
        lines[#lines + 1] = KTR.ErrText(handle.state.outfitError)
    end
    if display.item then
        lines[#lines + 1] = ('item: %s'):format(display.item.name)
        local md = display.item.metadata or {}
        if md.rarity then lines[#lines + 1] = 'rarity: ' .. tostring(md.rarity) end
        if md.achievement then lines[#lines + 1] = 'achievement: ' .. tostring(md.achievement) end
    end
    if KTRC.UI and KTRC.UI.ShowDetails then
        KTRC.UI.ShowDetails(display, lines)
    else
        local f = fw()
        if f then f.Notify(table.concat(lines, ' · ')) end
    end
end

local function buildOptions(display)
    local opts = {}

    opts[#opts + 1] = {
        label = KTR.L('inspect'), icon = 'fas fa-magnifying-glass',
        action = function(entity)
            local _, handle = KTRC.Streaming.DisplayForEntity(entity)
            inspect(display, handle)
        end,
    }

    if display.displayType == C.DisplayType.MANNEQUIN then
        opts[#opts + 1] = {
            label = KTR.L('try_outfit'), icon = 'fas fa-shirt',
            action = function()
                local ok, err = KTRC.Preview.TryOn(display.uid)
                if not ok and err then notifyErr(err) end
            end,
        }
    end

    -- owner/manager options: capability check happens on click (server is the
    -- authority; a denied action shows NOT_ALLOWED)
    local function managed(fn)
        return function(entity)
            local caps = KTR.RPC.Call('displays:capabilities', { uid = display.uid })
            if not caps or not caps.manage then return notifyErr(C.Err.NOT_ALLOWED) end
            fn(entity, caps)
        end
    end

    if display.displayType == C.DisplayType.MANNEQUIN then
        opts[#opts + 1] = {
            label = KTR.L('change_outfit'), icon = 'fas fa-arrows-rotate',
            action = managed(function()
                local cb = KTR.Bridge.Get('clothing')
                local outfit, err = cb.Capture(PlayerPedId())
                if not outfit then return notifyErr(C.Err.OUTFIT_INVALID) end
                if outfit.gender ~= display.gender then return notifyErr(C.Err.OUTFIT_INVALID) end
                local res, rerr = KTR.RPC.Call('displays:update',
                    { uid = display.uid, patch = { outfit = outfit } })
                if not res then return notifyErr(rerr) end
                local f = fw()
                if f then f.Notify(KTR.L('outfit_captured'), 'success') end
            end),
        }
        opts[#opts + 1] = {
            label = KTR.L('change_pose'), icon = 'fas fa-person',
            action = managed(function()
                if KTRC.UI and KTRC.UI.OpenPoseMenu then
                    KTRC.UI.OpenPoseMenu(display)
                end
            end),
        }
    end

    opts[#opts + 1] = {
        label = KTR.L('move'), icon = 'fas fa-up-down-left-right',
        action = managed(function()
            KTRC.Placement.MoveExisting(display)
        end),
    }

    if display.displayType == C.DisplayType.WEAPON_CASE
        or display.displayType == C.DisplayType.WEAPON_STAND then
        opts[#opts + 1] = {
            label = KTR.L('auto_rotate'), icon = 'fas fa-rotate',
            action = managed(function()
                if KTRC.UI and KTRC.UI.OpenRotateMenu then
                    KTRC.UI.OpenRotateMenu(display)
                end
            end),
        }
    end

    if display.item and display.displayType:find('^weapon_') then
        opts[#opts + 1] = {
            label = KTR.L('retrieve_weapon'), icon = 'fas fa-hand',
            action = managed(function()
                local idKey = ('%s_%d'):format(display.uid:sub(1, 8), GetGameTimer())
                local res, err = KTR.RPC.Call('weapons:retrieve',
                    { uid = display.uid, idKey = idKey })
                if not res then return notifyErr(err) end
                local f = fw()
                if f then f.Notify(KTR.L('removed'), 'success') end
            end),
        }
    else
        opts[#opts + 1] = {
            label = KTR.L('remove'), icon = 'fas fa-trash',
            action = managed(function()
                if KTRC.UI and KTRC.UI.ConfirmRemove then
                    KTRC.UI.ConfirmRemove(display)
                else
                    local res, err = KTR.RPC.Call('displays:delete', { uid = display.uid })
                    if not res then return notifyErr(err) end
                end
            end),
        }
    end
    return opts
end

function I.OnSpawn(display, handle)
    local t = target()
    if not t then return end
    local main = handle.entities[1]
    if main and DoesEntityExist(main) then
        t.AddEntity(main, buildOptions(display))
    end
end

function I.OnDespawn(uid, handle)
    local t = target()
    if not t then return end
    for _, e in ipairs(handle.entities or {}) do
        t.RemoveEntity(e)
    end
end
