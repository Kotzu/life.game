--[[
    Visitor try-on (brief §13): temporarily wear a display's outfit; the
    original appearance is ALWAYS restored — timeout, cancel, death, or
    resource restart (crash-safe via KVP snapshot).
]]

KTRC = KTRC or {}
KTRC.Preview = {}
local PV = KTRC.Preview

local KVP_KEY = 'kotzu_trophy_tryon_snapshot'
local session = nil -- { snapshot, deadline }

local function clothing()
    return KTR.Bridge.Get('clothing')
end

local function restore()
    if not session then return end
    local snap = session.snapshot
    session = nil
    DeleteResourceKvp(KVP_KEY)
    local cb = clothing()
    if cb and snap then
        cb.Apply(PlayerPedId(), snap)
        local fw = KTR.Bridge.Get('framework')
        if fw then fw.Notify(KTR.L('outfit_restored'), 'success') end
    end
end

function PV.IsActive() return session ~= nil end

---@return boolean ok, string|nil err
function PV.TryOn(uid)
    if session then restore() end
    local res, err = KTR.RPC.Call('outfit:forTryOn', { uid = uid })
    if not res then return false, err end

    local cb = clothing()
    local snapshot, capErr = cb.Capture(PlayerPedId())
    if not snapshot then return false, capErr end

    -- gender guard: only try outfits matching the player's model
    if snapshot.gender ~= res.outfit.gender then
        return false, KTR.Const.Err.OUTFIT_INVALID
    end

    local okApply, applyErr = cb.Apply(PlayerPedId(), res.outfit)
    if not okApply then return false, applyErr end

    -- Anchor the session to the display. A borrowed outfit must never leave the
    -- trophy room: if the player wanders off (e.g. toward a clothing store or a
    -- save trigger) the outfit is restored immediately. Without this, any
    -- resource that persists appearance while the preview is active would grant
    -- the borrowed clothes permanently — a real economy exploit on servers
    -- where clothing costs money.
    local anchor = KTRC.Streaming and KTRC.Streaming.EntityFor(uid)
    local anchorPos = anchor and DoesEntityExist(anchor)
        and GetEntityCoords(anchor) or GetEntityCoords(PlayerPedId())
    local model = GetEntityModel(PlayerPedId())

    session = {
        snapshot = snapshot,
        deadline = GetGameTimer() + (res.seconds or 60) * 1000,
        anchorPos = anchorPos,
        model = model,
    }
    SetResourceKvp(KVP_KEY, json.encode({ snapshot = snapshot, at = GetGameTimer() }))

    -- per-frame loop is acceptable here: it exists only while a try-on session
    -- is active (key presses must not be missed)
    CreateThread(function()
        while session do
            Wait(0)
            local ped = PlayerPedId()
            local reason
            if GetGameTimer() >= session.deadline then reason = 'timeout'
            elseif IsEntityDead(ped) then reason = 'death'
            elseif IsControlJustPressed(0, 177) then reason = 'cancel'
            elseif GetEntityModel(ped) ~= session.model then reason = 'model change'
            elseif #(GetEntityCoords(ped) - session.anchorPos)
                > KTR.Config.Interaction.PreviewLeashDistance then
                reason = 'walked away'
            end
            if reason then
                if KTR.Config.Debug then
                    print('[kotzu_trophy] try-on restored: ' .. reason)
                end
                restore()
                break
            end
        end
    end)
    return true
end

-- Exported so appearance/save resources can refuse to persist a borrowed
-- outfit:  if exports.kotzu_trophy_room:IsPreviewActive() then return end
exports('IsPreviewActive', function() return session ~= nil end)

function PV.Cancel()
    restore()
end

-- crash recovery: if a snapshot survived a restart, put the player back
CreateThread(function()
    Wait(3000) -- let the clothing system settle after (re)connect
    local stored = GetResourceKvpString(KVP_KEY)
    if stored then
        local ok, decoded = pcall(json.decode, stored)
        DeleteResourceKvp(KVP_KEY)
        if ok and decoded and decoded.snapshot then
            local cb = clothing()
            if cb then cb.Apply(PlayerPedId(), decoded.snapshot) end
            print('[kotzu_trophy] try-on snapshot restored after restart')
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then restore() end
end)
