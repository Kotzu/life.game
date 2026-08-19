--[[ Target bridge: qb-target (client). ]]

local impl = {
    detect = function() return KTR.Started('qb-target') end,
}

---options: array of { label, icon, action=fn(entity), canInteract=fn|nil }
function impl.AddEntity(entity, options)
    local qbOptions = {}
    for _, o in ipairs(options) do
        qbOptions[#qbOptions + 1] = {
            label = o.label,
            icon = o.icon or 'fas fa-cube',
            action = o.action,
            canInteract = o.canInteract,
        }
    end
    exports['qb-target']:AddTargetEntity(entity, {
        options = qbOptions,
        distance = KTR.Config.Interaction.TargetDistance,
    })
end

function impl.RemoveEntity(entity)
    pcall(function() exports['qb-target']:RemoveTargetEntity(entity) end)
end

KTR.Bridge.Register('target', 'qb-target', 10, impl)
