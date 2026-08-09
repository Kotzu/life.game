-- Admin/utility commands. All admin commands are restricted via ACE
-- permissions — see server.cfg.example:
--   add_ace group.admin lifecore.admin allow

local function isAdmin(source)
    return source == 0 or IsPlayerAceAllowed(source, 'lifecore.admin')
end

local function notify(source, message)
    if source == 0 then
        print('[lifecore] ' .. message)
    else
        TriggerClientEvent('lifecore:client:notify', source, message)
    end
end

RegisterCommand('setjob', function(source, args)
    if not isAdmin(source) then return notify(source, 'No permission.') end
    local target = LifeCore.GetPlayer(tonumber(args[1]))
    if not target then return notify(source, 'Player not found.') end
    if target.SetJob(args[2], tonumber(args[3]) or 0) then
        notify(source, ('Set %s to %s (grade %s).'):format(target.name, args[2], args[3] or 0))
    else
        notify(source, 'Unknown job or grade.')
    end
end, false)

RegisterCommand('givemoney', function(source, args)
    if not isAdmin(source) then return notify(source, 'No permission.') end
    local target = LifeCore.GetPlayer(tonumber(args[1]))
    if not target then return notify(source, 'Player not found.') end
    local account, amount = args[2], tonumber(args[3])
    if not amount or not target.AddMoney(account, amount) then
        return notify(source, 'Usage: /givemoney <id> <cash|bank> <amount>')
    end
    notify(source, ('Gave %s %s (%s).'):format(target.name, LifeUtils.FormatMoney(amount), account))
end, false)

RegisterCommand('giveitem', function(source, args)
    if not isAdmin(source) then return notify(source, 'No permission.') end
    local target = LifeCore.GetPlayer(tonumber(args[1]))
    if not target then return notify(source, 'Player not found.') end
    local item, count = args[2], tonumber(args[3]) or 1
    if not target.AddItem(item, count) then
        return notify(source, 'Unknown item: ' .. tostring(item))
    end
    notify(source, ('Gave %s %dx %s.'):format(target.name, count, item))
end, false)

RegisterCommand('saveall', function(source)
    if not isAdmin(source) then return notify(source, 'No permission.') end
    LifeCore.SaveAll()
    notify(source, 'All players saved.')
end, false)

-- Player-facing commands ----------------------------------------------------

RegisterCommand('pay', function(source, args)
    if source == 0 then return end
    local player = LifeCore.GetPlayer(source)
    local target = LifeCore.GetPlayer(tonumber(args[1]))
    local amount = math.floor(tonumber(args[2]) or 0)
    if not player or not target or target.source == player.source or amount <= 0 then
        return notify(source, 'Usage: /pay <id> <amount>')
    end
    if not player.RemoveMoney('cash', amount) then
        return notify(source, 'Not enough cash.')
    end
    target.AddMoney('cash', amount)
    notify(source, ('You paid %s %s.'):format(target.name, LifeUtils.FormatMoney(amount)))
    notify(target.source, ('%s paid you %s.'):format(player.name, LifeUtils.FormatMoney(amount)))
end, false)

RegisterCommand('job', function(source)
    if source == 0 then return end
    local player = LifeCore.GetPlayer(source)
    if not player then return end
    local job = player.GetJob()
    notify(source, ('Job: %s - %s'):format(job.label, job.gradeLabel))
end, false)
