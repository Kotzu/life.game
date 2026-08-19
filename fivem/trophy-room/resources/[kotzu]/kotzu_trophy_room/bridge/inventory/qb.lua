--[[ Inventory bridge: QBCore/qb-inventory (server). ]]

local impl = {
    detect = function()
        return KTR.Started('qb-core') and KTR.Started('qb-inventory')
    end,
}

local QBCore
local function core()
    if not QBCore then QBCore = exports['qb-core']:GetCoreObject() end
    return QBCore
end

function impl.Functional() return true end

local function metadataMatches(info, want)
    if not want then return true end
    info = info or {}
    for k, v in pairs(want) do
        if info[k] ~= v then return false end
    end
    return true
end

---Find the exact inventory slot holding an item matching metadata.
function impl.FindItem(src, name, metadata)
    local player = core().Functions.GetPlayer(src)
    if not player then return nil end
    for slot, item in pairs(player.PlayerData.items or {}) do
        if item and item.name == name and metadataMatches(item.info, metadata) then
            return { name = item.name, slot = item.slot or slot,
                     metadata = item.info or {}, count = item.amount or 1 }
        end
    end
    return nil
end

function impl.RemoveItem(src, name, slot, metadata)
    local player = core().Functions.GetPlayer(src)
    if not player then return false end
    local item = player.Functions.GetItemBySlot(slot)
    if not item or item.name ~= name or not metadataMatches(item.info, metadata) then
        return false
    end
    return player.Functions.RemoveItem(name, 1, slot) == true
end

function impl.AddItem(src, name, metadata)
    local player = core().Functions.GetPlayer(src)
    if not player then return false end
    return player.Functions.AddItem(name, 1, nil, metadata or {}) == true
end

KTR.Bridge.Register('inventory', 'qb-inventory', 10, impl)
