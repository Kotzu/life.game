--[[ Target bridge: ox_target (client). ]]

local impl = {
    detect = function() return KTR.Started('ox_target') end,
}

function impl.AddEntity(entity, options)
    local oxOptions = {}
    for i, o in ipairs(options) do
        oxOptions[#oxOptions + 1] = {
            name = ('kotzu_trophy_%d_%d'):format(entity, i),
            label = o.label,
            icon = o.icon or 'fa-solid fa-cube',
            distance = KTR.Config.Interaction.TargetDistance,
            onSelect = function(data) o.action(data.entity) end,
            canInteract = o.canInteract and function(ent) return o.canInteract(ent) end or nil,
        }
    end
    exports.ox_target:addLocalEntity(entity, oxOptions)
end

function impl.RemoveEntity(entity)
    pcall(function() exports.ox_target:removeLocalEntity(entity) end)
end

KTR.Bridge.Register('target', 'ox_target', 20, impl)
