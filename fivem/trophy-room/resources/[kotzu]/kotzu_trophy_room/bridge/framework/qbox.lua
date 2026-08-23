--[[
    Framework bridge: Qbox (qbx_core). Shared file, side-gated.

    Verified against the real qbx_core source (github.com/Qbox-project/qbx_core):
    - server exports: GetPlayer(src) -> player with .PlayerData
      (citizenid, charinfo, job = { name, grade = { name, level } }),
      HasPermission(src, perm), Notify(src, text, type)
    - permissions are ACE-based (IsPlayerAceAllowed(src, 'admin'))
    - client notifications: ox_lib 'ox_lib:notify' event (lib.notify)

    Priority 20 beats the qbcore bridge (10): Qbox servers may also expose a
    qb-core compat resource, and qbx_core must win when both are present.
]]

local isServer = IsDuplicityVersion()

local impl = {
    detect = function()
        return KTR.Started('qbx_core')
    end,
}

if isServer then
    function impl.GetIdentity(src)
        local ok, player = pcall(function()
            return exports.qbx_core:GetPlayer(src)
        end)
        if not ok or not player then return nil end
        local pd = player.PlayerData
        if not pd then return nil end
        return {
            source = src,
            citizenid = pd.citizenid,
            name = (pd.charinfo and (pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname))
                or GetPlayerName(src),
            job = pd.job and pd.job.name or nil,
            grade = pd.job and pd.job.grade and pd.job.grade.level or 0,
        }
    end

    function impl.IsAdmin(src)
        if IsPlayerAceAllowed(src, KTR.Config.AdminAce) then return true end
        if IsPlayerAceAllowed(src, 'admin') then return true end
        local ok, res = pcall(function()
            return exports.qbx_core:HasPermission(src, 'admin')
        end)
        return ok and res == true
    end

    function impl.Notify(src, msg, kind)
        local ok = pcall(function()
            exports.qbx_core:Notify(src, msg, kind or 'inform')
        end)
        if not ok then
            TriggerClientEvent('chat:addMessage', src,
                { color = { 235, 195, 80 }, args = { 'trophy', msg } })
        end
    end
else
    function impl.Notify(msg, kind)
        if KTR.Started('ox_lib') then
            TriggerEvent('ox_lib:notify', {
                description = msg,
                type = kind == 'error' and 'error' or (kind == 'success' and 'success' or 'inform'),
            })
        else
            TriggerEvent('chat:addMessage',
                { color = { 235, 195, 80 }, args = { 'trophy', msg } })
        end
    end

    function impl.GetGender()
        local model = GetEntityModel(PlayerPedId())
        if model == joaat(KTR.Const.Model.female) then return KTR.Const.Gender.FEMALE end
        return KTR.Const.Gender.MALE
    end
end

KTR.Bridge.Register('framework', 'qbox', 20, impl)
