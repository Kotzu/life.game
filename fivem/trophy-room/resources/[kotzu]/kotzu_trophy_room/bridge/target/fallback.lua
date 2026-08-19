--[[
    Target bridge: keypress fallback (client) — used when neither qb-target nor
    ox_target is running. E opens the first option; the options menu is routed
    through NUI. Proximity check runs at 250 ms; a per-frame loop exists ONLY
    while a prompt is visible.
]]

local impl = {
    detect = function() return true end,
}

local tracked = {} -- entity -> options
local promptEntity = nil

function impl.AddEntity(entity, options)
    tracked[entity] = options
end

function impl.RemoveEntity(entity)
    tracked[entity] = nil
    if promptEntity == entity then promptEntity = nil end
end

local function nearestTracked()
    local pos = GetEntityCoords(PlayerPedId())
    local best, bestDist
    for entity in pairs(tracked) do
        if DoesEntityExist(entity) then
            local d = #(GetEntityCoords(entity) - pos)
            if d <= KTR.Config.Interaction.TargetDistance and (not bestDist or d < bestDist) then
                best, bestDist = entity, d
            end
        else
            tracked[entity] = nil
        end
    end
    return best
end

CreateThread(function()
    while true do
        promptEntity = next(tracked) and nearestTracked() or nil
        if promptEntity then
            -- per-frame only while a prompt is on screen
            while promptEntity and DoesEntityExist(promptEntity) do
                local opts = tracked[promptEntity]
                if not opts then break end
                SetTextFont(4) SetTextScale(0.32, 0.32) SetTextCentre(true)
                SetTextColour(240, 240, 240, 220)
                BeginTextCommandDisplayText('STRING')
                AddTextComponentSubstringPlayerName(('~y~[E]~s~ %s'):format(opts[1] and opts[1].label or 'Interact'))
                EndTextCommandDisplayText(0.5, 0.9)
                if IsControlJustPressed(0, 38) then -- E
                    local menu = {}
                    for _, o in ipairs(opts) do
                        if not o.canInteract or o.canInteract(promptEntity) then
                            menu[#menu + 1] = o
                        end
                    end
                    if #menu == 1 then
                        menu[1].action(promptEntity)
                    elseif #menu > 1 and KTR.UI and KTR.UI.OpenOptionMenu then
                        KTR.UI.OpenOptionMenu(menu, promptEntity)
                    end
                end
                Wait(0)
                if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(promptEntity)) >
                    KTR.Config.Interaction.TargetDistance then
                    promptEntity = nil
                end
            end
        end
        Wait(250)
    end
end)

KTR.Bridge.Register('target', 'fallback', 0, impl)
