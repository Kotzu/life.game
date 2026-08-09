-- Player lifecycle: connect -> load from DB -> play -> save on drop.

local function loadPlayer(source)
    local identifier = LifeCore.GetIdentifier(source)
    if not identifier then
        DropPlayer(source, ('[lifecore] Could not resolve your %s identifier.'):format(Config.IdentifierType))
        return
    end

    MySQL.single('SELECT * FROM players WHERE identifier = ?', { identifier }, function(row)
        -- The player may have disconnected while the query ran.
        if GetPlayerName(source) == nil then return end

        local player = LifePlayer.new(source, identifier, row)
        LifeCore.Players[source] = player

        if not row then
            MySQL.insert(
                'INSERT INTO players (identifier, name, money, job, inventory, metadata, position) VALUES (?, ?, ?, ?, ?, ?, ?)',
                {
                    identifier,
                    player.name,
                    json.encode(player.money),
                    json.encode(player.job),
                    json.encode(player.inventory),
                    json.encode(player.metadata),
                    json.encode(player.position),
                }
            )
        end

        TriggerClientEvent('lifecore:client:playerLoaded', source, player.GetClientData())
        TriggerEvent('lifecore:server:playerLoaded', source, player)
        print(('[lifecore] %s (%s) loaded'):format(player.name, identifier))
    end)
end

RegisterNetEvent('lifecore:server:requestLoad', function()
    local src = source
    if LifeCore.Players[src] then
        -- Client resource restarted; resend current state instead of reloading.
        TriggerClientEvent('lifecore:client:playerLoaded', src, LifeCore.Players[src].GetClientData())
        return
    end
    loadPlayer(src)
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    local player = LifeCore.Players[src]
    if not player then return end
    player.Save(function()
        LifeUtils.Debug('saved on drop', player.identifier)
    end)
    LifeCore.Players[src] = nil
    TriggerEvent('lifecore:server:playerDropped', src, player.identifier, reason)
    print(('[lifecore] %s (%s) dropped: %s'):format(player.name, player.identifier, reason))
end)

-- Autosave -----------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(Config.SaveInterval)
        LifeCore.SaveAll()
        LifeUtils.Debug('autosaved', #LifeCore.GetPlayers(), 'players')
    end
end)

-- Save everyone when the resource stops (server shutdown, restart).
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    LifeCore.SaveAll()
end)

-- Paychecks & status decay --------------------------------------------------

CreateThread(function()
    while true do
        Wait(Config.StatusTickRate)
        for _, player in pairs(LifeCore.Players) do
            if Config.StatusEnabled then
                local hunger = LifeUtils.Clamp((player.GetMetadata('hunger') or 100) - Config.HungerPerTick, 0, 100)
                local thirst = LifeUtils.Clamp((player.GetMetadata('thirst') or 100) - Config.ThirstPerTick, 0, 100)
                player.SetMetadata('hunger', hunger)
                player.SetMetadata('thirst', thirst)
            end
        end
    end
end)

-- Salary every 10 minutes.
CreateThread(function()
    while true do
        Wait(10 * 60 * 1000)
        for _, player in pairs(LifeCore.Players) do
            local job = player.GetJob()
            if job.salary and job.salary > 0 then
                player.AddMoney('bank', job.salary)
                TriggerClientEvent('lifecore:client:notify', player.source,
                    ('Paycheck received: %s'):format(LifeUtils.FormatMoney(job.salary)))
            end
        end
    end
end)

-- Built-in usable items ------------------------------------------------------

LifeCore.RegisterUsableItem('water', function(source)
    local player = LifeCore.GetPlayer(source)
    if player.RemoveItem('water', 1) then
        player.SetMetadata('thirst', LifeUtils.Clamp((player.GetMetadata('thirst') or 0) + 35, 0, 100))
        TriggerClientEvent('lifecore:client:notify', source, 'You drank some water.')
    end
end)

LifeCore.RegisterUsableItem('bread', function(source)
    local player = LifeCore.GetPlayer(source)
    if player.RemoveItem('bread', 1) then
        player.SetMetadata('hunger', LifeUtils.Clamp((player.GetMetadata('hunger') or 0) + 25, 0, 100))
        TriggerClientEvent('lifecore:client:notify', source, 'You ate some bread.')
    end
end)

LifeCore.RegisterUsableItem('burger', function(source)
    local player = LifeCore.GetPlayer(source)
    if player.RemoveItem('burger', 1) then
        player.SetMetadata('hunger', LifeUtils.Clamp((player.GetMetadata('hunger') or 0) + 45, 0, 100))
        TriggerClientEvent('lifecore:client:notify', source, 'You ate a burger.')
    end
end)
