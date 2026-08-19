--[[ Framework bridge: QBCore. Shared file, side-gated. ]]

local isServer = IsDuplicityVersion()

local impl = {
    detect = function()
        return KTR.Started('qb-core')
    end,
}

local QBCore
local function core()
    if not QBCore then QBCore = exports['qb-core']:GetCoreObject() end
    return QBCore
end

if isServer then
    ---@return table|nil identity { citizenid, name, job, grade, source }
    function impl.GetIdentity(src)
        local player = core().Functions.GetPlayer(src)
        if not player then return nil end
        local pd = player.PlayerData
        return {
            source = src,
            citizenid = pd.citizenid,
            name = (pd.charinfo and (pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname)) or GetPlayerName(src),
            job = pd.job and pd.job.name or nil,
            grade = pd.job and pd.job.grade and pd.job.grade.level or 0,
        }
    end

    function impl.IsAdmin(src)
        if IsPlayerAceAllowed(src, KTR.Config.AdminAce) then return true end
        local ok, res = pcall(function()
            return core().Functions.HasPermission(src, 'admin')
        end)
        return ok and res or false
    end

    function impl.Notify(src, msg, kind)
        TriggerClientEvent('QBCore:Notify', src, msg, kind or 'primary')
    end
else
    function impl.Notify(msg, kind)
        TriggerEvent('QBCore:Notify', msg, kind or 'primary')
    end

    function impl.GetGender()
        -- model-based, robust regardless of character data
        local model = GetEntityModel(PlayerPedId())
        if model == joaat(KTR.Const.Model.female) then return KTR.Const.Gender.FEMALE end
        return KTR.Const.Gender.MALE
    end
end

KTR.Bridge.Register('framework', 'qbcore', 10, impl)
