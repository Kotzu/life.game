-- Core server-side API. Other resources get at this via:
--   local LifeCore = exports['lifecore']:GetCore()

LifeCore = {
    Players = {}, -- source -> player object
}

--- Resolve the configured identifier for a connected player.
---@param source number
---@return string|nil
function LifeCore.GetIdentifier(source)
    local prefix = Config.IdentifierType .. ':'
    for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
        if identifier:sub(1, #prefix) == prefix then
            return identifier
        end
    end
    return nil
end

--- Get a loaded player by server id.
---@param source number
---@return table|nil
function LifeCore.GetPlayer(source)
    return LifeCore.Players[tonumber(source)]
end

--- Get a loaded player by identifier.
---@param identifier string
---@return table|nil
function LifeCore.GetPlayerByIdentifier(identifier)
    for _, player in pairs(LifeCore.Players) do
        if player.identifier == identifier then return player end
    end
    return nil
end

--- All loaded players.
---@return table[] array of player objects
function LifeCore.GetPlayers()
    local players = {}
    for _, player in pairs(LifeCore.Players) do
        players[#players + 1] = player
    end
    return players
end

--- All loaded players with a given job.
---@param jobName string
---@return table[]
function LifeCore.GetPlayersByJob(jobName)
    local players = {}
    for _, player in pairs(LifeCore.Players) do
        if player.job.name == jobName then players[#players + 1] = player end
    end
    return players
end

--- Save every loaded player.
function LifeCore.SaveAll()
    for _, player in pairs(LifeCore.Players) do
        player.Save()
    end
end

-- Usable item handlers: RegisterUsableItem('water', function(source) ... end)
local usableItems = {}

---@param item string item name from shared/items.lua
---@param handler fun(source: number)
function LifeCore.RegisterUsableItem(item, handler)
    usableItems[item] = handler
end

--- Consume-path entry point; fired by the client when a player uses an item.
---@param source number
---@param item string
function LifeCore.UseItem(source, item)
    local player = LifeCore.GetPlayer(source)
    if not player then return end
    local def = LifeItems[item]
    if not def or not def.usable then return end
    if player.GetItemCount(item) <= 0 then return end
    local handler = usableItems[item]
    if handler then
        handler(source)
    else
        LifeUtils.Debug('no handler registered for usable item', item)
    end
end

exports('GetCore', function()
    return LifeCore
end)

AddEventHandler('lifecore:server:useItem', function(item)
    LifeCore.UseItem(source, item)
end)

RegisterNetEvent('lifecore:server:requestUseItem', function(item)
    LifeCore.UseItem(source, tostring(item))
end)
