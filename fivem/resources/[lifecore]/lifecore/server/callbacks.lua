-- Server-side half of the request/response callback system.
-- Register with:
--   LifeCore.RegisterCallback('myresource:getData', function(source, cb, arg1)
--       cb(someData)
--   end)
-- Clients invoke via LifeCore.TriggerCallback (see client/callbacks.lua).

local callbacks = {}

---@param name string
---@param handler fun(source: number, cb: fun(...), ...)
function LifeCore.RegisterCallback(name, handler)
    callbacks[name] = handler
end

RegisterNetEvent('lifecore:cb:trigger', function(name, requestId, ...)
    local src = source
    local handler = callbacks[name]
    if not handler then
        LifeUtils.Debug('unknown callback requested', name)
        TriggerClientEvent('lifecore:cb:response', src, requestId)
        return
    end
    handler(src, function(...)
        TriggerClientEvent('lifecore:cb:response', src, requestId, ...)
    end, ...)
end)

-- Built-in callbacks -------------------------------------------------------

LifeCore.RegisterCallback('lifecore:getPlayerData', function(source, cb)
    local player = LifeCore.GetPlayer(source)
    cb(player and player.GetClientData() or nil)
end)

LifeCore.RegisterCallback('lifecore:getOnlineCount', function(_, cb)
    cb(#LifeCore.GetPlayers())
end)
