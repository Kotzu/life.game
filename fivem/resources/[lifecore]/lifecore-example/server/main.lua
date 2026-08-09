-- Example: everything a gameplay resource typically needs from the core.

local LifeCore = exports['lifecore']:GetCore()

-- React to lifecycle events.
AddEventHandler('lifecore:server:playerLoaded', function(source, player)
    print(('[example] %s loaded with %s cash'):format(player.name, player.GetMoney('cash')))
end)

AddEventHandler('lifecore:server:jobChanged', function(source, jobName, grade)
    print(('[example] player %d is now %s (grade %d)'):format(source, jobName, grade))
end)

-- Register a server callback the client can query.
LifeCore.RegisterCallback('example:getBalance', function(source, cb)
    local player = LifeCore.GetPlayer(source)
    cb(player and player.GetMoney('bank') or 0)
end)

-- Register a usable item handler.
LifeCore.RegisterUsableItem('bandage', function(source)
    local player = LifeCore.GetPlayer(source)
    if player.RemoveItem('bandage', 1) then
        local ped = GetPlayerPed(source)
        SetEntityHealth(ped, math.min(GetEntityHealth(ped) + 25, 200))
        TriggerClientEvent('lifecore:client:notify', source, 'You applied a bandage.')
    end
end)

-- A simple paid command: costs cash, pays into bank.
RegisterCommand('work', function(source)
    if source == 0 then return end
    local player = LifeCore.GetPlayer(source)
    if not player then return end
    player.AddMoney('bank', 25)
    TriggerClientEvent('lifecore:client:notify', source, 'You did some odd jobs and earned $25.')
end, false)
