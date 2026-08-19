--[[ Inventory bridge: ox_inventory (server). ]]

local impl = {
    detect = function() return KTR.Started('ox_inventory') end,
}

function impl.Functional() return true end

local function metadataMatches(md, want)
    if not want then return true end
    md = md or {}
    for k, v in pairs(want) do
        if md[k] ~= v then return false end
    end
    return true
end

function impl.FindItem(src, name, metadata)
    local slots = exports.ox_inventory:Search(src, 'slots', name)
    if type(slots) ~= 'table' then return nil end
    for _, item in pairs(slots) do
        if metadataMatches(item.metadata, metadata) then
            return { name = item.name, slot = item.slot,
                     metadata = item.metadata or {}, count = item.count or 1 }
        end
    end
    return nil
end

function impl.RemoveItem(src, name, slot, metadata)
    return exports.ox_inventory:RemoveItem(src, name, 1, metadata, slot) == true
end

function impl.AddItem(src, name, metadata)
    local ok = exports.ox_inventory:AddItem(src, name, 1, metadata or {})
    return ok == true or type(ok) == 'table'
end

KTR.Bridge.Register('inventory', 'ox_inventory', 20, impl)
