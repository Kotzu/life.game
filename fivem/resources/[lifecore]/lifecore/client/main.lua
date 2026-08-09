-- Client bootstrap: request player state from the server, spawn the ped at
-- the saved position, and keep basic HUD info available.

local firstSpawn = true

AddEventHandler('playerSpawned', function()
    if not firstSpawn then return end
    firstSpawn = false
    TriggerServerEvent('lifecore:server:requestLoad')
end)

-- Resource restart while already in-game: re-request state immediately.
CreateThread(function()
    if NetworkIsSessionStarted() then
        TriggerServerEvent('lifecore:server:requestLoad')
    end
end)

RegisterNetEvent('lifecore:client:playerLoaded', function(data)
    local alreadyLoaded = LifeCore.PlayerLoaded
    LifeCore.PlayerData = data
    LifeCore.PlayerLoaded = true

    if not alreadyLoaded and data.position then
        local ped = PlayerPedId()
        SetEntityCoordsNoOffset(ped, data.position.x, data.position.y, data.position.z, false, false, false)
        SetEntityHeading(ped, data.position.heading or 0.0)
    end

    TriggerEvent('lifecore:client:loaded', data)
    LifeUtils.Debug('player state received')
end)

-- Low hunger/thirst health drain -------------------------------------------

CreateThread(function()
    while true do
        Wait(10000)
        if Config.StatusEnabled and LifeCore.PlayerLoaded then
            local meta = LifeCore.PlayerData.metadata or {}
            if (meta.hunger or 100) <= 0 or (meta.thirst or 100) <= 0 then
                local ped = PlayerPedId()
                local health = GetEntityHealth(ped)
                if health > 100 then
                    SetEntityHealth(ped, health - 5)
                end
            end
        end
    end
end)

-- /status: quick self-check of money, job, hunger and thirst.
RegisterCommand('status', function()
    if not LifeCore.PlayerLoaded then return end
    local data = LifeCore.PlayerData
    local meta = data.metadata or {}
    LifeCore.Notify(('Cash: %s | Bank: %s'):format(
        LifeUtils.FormatMoney(data.money.cash or 0),
        LifeUtils.FormatMoney(data.money.bank or 0)))
    LifeCore.Notify(('Hunger: %d%% | Thirst: %d%%'):format(meta.hunger or 100, meta.thirst or 100))
end, false)

-- /use <item>: consume a usable item.
RegisterCommand('use', function(_, args)
    if not args[1] then
        LifeCore.Notify('Usage: /use <item>')
        return
    end
    LifeCore.UseItem(args[1])
end, false)
