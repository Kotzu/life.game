-- Example client: consuming core state, updates, and callbacks.

local LifeCore = exports['lifecore']:GetCore()

-- Fires once when the initial player state arrives.
AddEventHandler('lifecore:client:loaded', function(data)
    LifeCore.Notify(('Welcome back, %s!'):format(data.name))
end)

-- Fires whenever a slice of player state changes (money, job, inventory, metadata).
AddEventHandler('lifecore:client:playerUpdated', function(key, value)
    if key == 'job' then
        LifeCore.Notify('Your job changed to ' .. value.name)
    end
end)

-- Query a server callback (async style).
RegisterCommand('balance', function()
    LifeCore.TriggerCallback('example:getBalance', function(balance)
        LifeCore.Notify('Bank balance: ' .. LifeUtils.FormatMoney(balance))
    end)
end, false)

-- Query a server callback (await style, inside a thread).
RegisterCommand('online', function()
    CreateThread(function()
        local count = LifeCore.AwaitCallback('lifecore:getOnlineCount')
        LifeCore.Notify(('Players online: %d'):format(count))
    end)
end, false)
