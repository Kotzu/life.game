--[[ Framework bridge: standalone fallback (license identifier, ace perms). ]]

local isServer = IsDuplicityVersion()

local impl = {
    detect = function() return true end, -- always available, lowest priority
}

if isServer then
    function impl.GetIdentity(src)
        local license
        for i = 0, GetNumPlayerIdentifiers(src) - 1 do
            local id = GetPlayerIdentifier(src, i)
            if id and id:find('^license:') then license = id break end
        end
        if not license then return nil end
        return { source = src, citizenid = license, name = GetPlayerName(src), job = nil, grade = 0 }
    end

    function impl.IsAdmin(src)
        return IsPlayerAceAllowed(src, KTR.Config.AdminAce)
    end

    function impl.Notify(src, msg, kind)
        TriggerClientEvent('chat:addMessage', src,
            { color = { 235, 195, 80 }, args = { 'trophy', msg } })
    end
else
    function impl.Notify(msg)
        TriggerEvent('chat:addMessage', { color = { 235, 195, 80 }, args = { 'trophy', msg } })
    end

    function impl.GetGender()
        local model = GetEntityModel(PlayerPedId())
        if model == joaat(KTR.Const.Model.female) then return KTR.Const.Gender.FEMALE end
        return KTR.Const.Gender.MALE
    end
end

KTR.Bridge.Register('framework', 'standalone', 0, impl)
