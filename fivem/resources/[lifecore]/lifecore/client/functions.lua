-- Client-side API. Other resources get at this via:
--   local LifeCore = exports['lifecore']:GetCore()

LifeCore = {
    PlayerData = nil, -- nil until lifecore:client:playerLoaded fires
    PlayerLoaded = false,
}

--- Current player state snapshot (money, job, inventory, metadata).
---@return table|nil
function LifeCore.GetPlayerData()
    return LifeCore.PlayerData
end

--- True once the server has sent the initial player state.
---@return boolean
function LifeCore.IsPlayerLoaded()
    return LifeCore.PlayerLoaded
end

--- Ask the server to consume a usable item.
---@param item string
function LifeCore.UseItem(item)
    TriggerServerEvent('lifecore:server:requestUseItem', item)
end

--- Notification. Routed through the 'notify' service when one is registered
--- (e.g. the lifecore-hud toasts); falls back to chat otherwise.
---@param message string
---@param level string|nil 'info' | 'success' | 'error'
function LifeCore.Notify(message, level)
    local notify = LifeServices.Get('notify')
    if notify then
        notify.Send(message, level or 'info')
        return
    end
    TriggerEvent('chat:addMessage', {
        color = { 116, 199, 236 },
        args = { 'life', message },
    })
end

exports('GetCore', function()
    return LifeCore
end)

-- Service registry (see shared/services.lua for the full contract docs).
exports('RegisterService', function(name, impl)
    LifeServices.Register(name, impl, GetInvokingResource() or GetCurrentResourceName())
end)

exports('GetService', function(name)
    return LifeServices.Get(name)
end)

RegisterNetEvent('lifecore:client:notify', function(message, level)
    LifeCore.Notify(tostring(message), level)
end)

RegisterNetEvent('lifecore:player:update', function(key, value)
    if not LifeCore.PlayerData then return end
    LifeCore.PlayerData[key] = value
    TriggerEvent('lifecore:client:playerUpdated', key, value)
end)
