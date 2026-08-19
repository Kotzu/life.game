--[[
    kotzu_arch_proof — server: persists proof-suite evidence to
    arch_proof_results.json inside this resource's folder.
    Restricted to ace 'command' holders (console / admins) to avoid abuse.
]]

local function isAllowed(src)
    return src == 0 or IsPlayerAceAllowed(src, 'command') or IsPlayerAceAllowed(src, 'kotzu.archproof')
end

RegisterNetEvent('kotzu_arch_proof:submit', function(results, meta)
    local src = source
    if not isAllowed(src) then
        print(('[archproof] rejected submission from unauthorized source %d'):format(src))
        return
    end
    if type(results) ~= 'table' or type(meta) ~= 'table' then
        print('[archproof] malformed submission rejected')
        return
    end

    local payload = {
        schema = 'kotzu_arch_proof/1',
        submittedBy = src == 0 and 'console' or GetPlayerName(src),
        serverTime = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        meta = meta,
        results = results,
    }

    local summary = { PASS = 0, FAIL = 0, SKIPPED = 0, NOT_YET_STREAMED = 0, INFO = 0 }
    for _, r in ipairs(results) do
        if type(r) == 'table' and summary[r.status] ~= nil then
            summary[r.status] = summary[r.status] + 1
        end
    end
    payload.summary = summary

    local ok = SaveResourceFile(GetCurrentResourceName(), 'arch_proof_results.json',
        json.encode(payload), -1)
    print(('[archproof] results %s — PASS=%d FAIL=%d SKIPPED=%d NOT_YET_STREAMED=%d INFO=%d')
        :format(ok and 'saved to arch_proof_results.json' or 'FAILED TO SAVE',
            summary.PASS, summary.FAIL, summary.SKIPPED, summary.NOT_YET_STREAMED, summary.INFO))
end)
