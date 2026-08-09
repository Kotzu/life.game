-- HUD client. Everything is push-based: player state changes arrive as
-- lifecore events and are forwarded to the NUI. The only polling is a slow
-- 250ms tick for values that have no event (health/armor/pause menu), which
-- costs nothing next to a per-frame loop.

local LifeCore = exports['lifecore']:GetCore()

-- Register as the framework's notification provider: every LifeCore.Notify
-- anywhere on the server/client now renders as a HUD toast instead of chat.
exports['lifecore']:RegisterService('notify', {
    Send = function(message, level)
        SendNUIMessage({
            action = 'notify',
            message = tostring(message),
            level = level or 'info',
        })
    end,
})

local function healthPercent(ped)
    local health = GetEntityHealth(ped)
    local max = GetEntityMaxHealth(ped)
    -- GTA peds are "empty" at 100 health, not 0.
    if max <= 100 then return 0 end
    return math.max(0, math.min(100, (health - 100) / (max - 100) * 100))
end

local function pushPlayerState()
    local data = LifeCore.GetPlayerData()
    if not data then return end
    local meta = data.metadata or {}
    local jobDef = LifeJobs[data.job.name]
    local gradeDef = jobDef and jobDef.grades[data.job.grade]
    SendNUIMessage({
        action = 'state',
        money = data.money,
        job = {
            name = data.job.name,
            label = jobDef and jobDef.label or data.job.name,
            gradeLabel = gradeDef and gradeDef.label or '',
        },
        hunger = meta.hunger or 100,
        thirst = meta.thirst or 100,
    })
end

AddEventHandler('lifecore:client:loaded', function()
    SendNUIMessage({ action = 'visible', visible = true })
    pushPlayerState()
end)

AddEventHandler('lifecore:client:playerUpdated', function(key)
    if key == 'money' or key == 'metadata' or key == 'job' then
        pushPlayerState()
    end
end)

-- Slow tick: vitals + pause menu visibility.
CreateThread(function()
    local wasPaused = false
    while true do
        Wait(250)
        if LifeCore.IsPlayerLoaded() then
            local ped = PlayerPedId()
            SendNUIMessage({
                action = 'vitals',
                health = healthPercent(ped),
                armor = GetPedArmour(ped),
            })
            local paused = IsPauseMenuActive()
            if paused ~= wasPaused then
                wasPaused = paused
                SendNUIMessage({ action = 'visible', visible = not paused })
            end
        end
    end
end)
