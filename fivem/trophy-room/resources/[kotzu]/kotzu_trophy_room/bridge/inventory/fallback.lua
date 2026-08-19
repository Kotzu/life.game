--[[
    Inventory bridge: fallback (server). Non-functional by design: with no
    recognized inventory, weapon displays are REFUSED (never faked) —
    Config.Weapons.RequireInventoryBridge gates the whole weapon feature.
]]

local impl = {
    detect = function() return true end,
}

function impl.Functional() return false end
function impl.FindItem() return nil end
function impl.RemoveItem() return false end
function impl.AddItem() return false end

KTR.Bridge.Register('inventory', 'fallback', 0, impl)
