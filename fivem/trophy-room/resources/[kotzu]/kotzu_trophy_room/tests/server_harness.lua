--[[
    Server test harness (brief §20/§21). Gated by Config.DevCommands and admin
    ace (or console). Includes the weapon-transaction rollback tests (T18).
]]

if not KTR.Config.DevCommands then return end

local C = KTR.Const

local function allowed(src)
    return src == 0 or KTRS.Perms.IsAdmin(src)
end

local function say(src, msg)
    if src == 0 then print('[kmq] ' .. msg)
    else TriggerClientEvent('chat:addMessage', src,
        { color = { 120, 200, 255 }, args = { 'kmq', msg } }) end
end

-- test shells (routing-bucket isolation, acceptance T8/T11)
RegisterCommand('kmq:testshell', function(src, args)
    if not allowed(src) or src == 0 then return end
    local which = args[1] or 'a'
    local shell = nil
    for _, s in ipairs(KTR.Config.Housing.TestShells) do
        if s.shellId:sub(-1) == which then shell = s break end
    end
    if not shell then say(src, 'usage: /kmq:testshell a|b') return end
    SetPlayerRoutingBucket(src, shell.bucket)
    TriggerClientEvent('kotzu_trophy:test:enterShell', src, {
        shellId = shell.shellId, bucket = shell.bucket,
        origin = { x = shell.origin.x, y = shell.origin.y, z = shell.origin.z, w = shell.origin.w },
    })
end, true)

RegisterCommand('kmq:leaveshell', function(src)
    if not allowed(src) or src == 0 then return end
    SetPlayerRoutingBucket(src, 0)
    TriggerClientEvent('kotzu_trophy:test:exitShell', src)
end, true)

RegisterCommand('kmq:validate_db', function(src)
    if not allowed(src) then return end
    local problems = KTRS.Repo.ValidateDb()
    if #problems == 0 then
        say(src, 'DB/cache/locks consistent — no problems')
    else
        for _, p in ipairs(problems) do say(src, 'PROBLEM: ' .. p) end
    end
end, true)

RegisterCommand('kmq:bridges', function(src)
    if not allowed(src) then return end
    say(src, json.encode(KTR.Bridge.Describe()))
end, true)

-- ------------------------------------------------ weapon transaction tests

---T18a: place with an item the player does not own -> ITEM_MISSING, lock closed.
---T18b: idempotency replay -> second call with same key returns same outcome.
---T18c: retrieve nonexistent display -> NOT_FOUND, no side effects.
RegisterCommand('kmq:weapon_tx_test', function(src)
    if not allowed(src) or src == 0 then
        say(src, 'run as a connected admin player')
        return
    end
    CreateThread(function()
        local results = {}
        local function check(name, cond, detail)
            results[#results + 1] = ('%s: %s %s'):format(name, cond and 'PASS' or 'FAIL', detail or '')
        end

        local fakeDisplay = {
            displayType = C.DisplayType.WEAPON_STAND,
            scopeType = C.ScopeType.WORLD,
            transform = { x = 0.0, y = 0.0, z = 72.0, heading = 0.0 },
            item = { name = 'weapon_kmq_does_not_exist', metadata = {} },
            owner = 'kmq_test',
        }
        local key1 = ('kmqtest_%d_a'):format(os.time())

        -- T18a
        local uid, err = KTRS.Tx.PlaceWeapon(src, fakeDisplay, key1)
        check('T18a place-missing-item', uid == nil and err == C.Err.ITEM_MISSING,
            ('uid=%s err=%s'):format(tostring(uid), tostring(err)))
        local lock = MySQL.single.await(
            'SELECT state FROM kotzu_tx_locks WHERE idempotency_key = ?', { key1 })
        check('T18a lock-closed', lock ~= nil and lock.state == 'failed',
            'state=' .. tostring(lock and lock.state))

        -- T18b: replay with the same key must not re-execute
        local uid2, err2 = KTRS.Tx.PlaceWeapon(src, fakeDisplay, key1)
        check('T18b idempotent-replay', uid2 == nil and err2 == C.Err.TX_FAILED,
            ('err=%s (replay of failed key correctly refused)'):format(tostring(err2)))

        -- T18c: retrieve nonexistent
        local ok3, err3 = KTRS.Tx.RetrieveWeapon(src, '00000000-0000-4000-8000-000000000000',
            ('kmqtest_%d_c'):format(os.time()))
        check('T18c retrieve-nonexistent', ok3 == false and err3 == C.Err.NOT_FOUND,
            'err=' .. tostring(err3))

        -- T18d: full cycle if the player owns a weapon_pistol (optional)
        local inv = KTR.Bridge.Get('inventory')
        local item = inv and inv.Functional() and inv.FindItem(src, 'weapon_pistol', nil)
        if item then
            local d2 = {
                displayType = C.DisplayType.WEAPON_STAND,
                scopeType = C.ScopeType.WORLD,
                transform = { x = 0.0, y = 0.0, z = 72.0, heading = 0.0 },
                item = { name = 'weapon_pistol', metadata = {} },
                owner = 'kmq_test', bucket = GetPlayerRoutingBucket(src),
            }
            local key2 = ('kmqtest_%d_d'):format(os.time())
            local uid4, err4 = KTRS.Tx.PlaceWeapon(src, d2, key2)
            check('T18d place-owned', uid4 ~= nil, 'err=' .. tostring(err4))
            if uid4 then
                local stillHave = inv.FindItem(src, 'weapon_pistol',
                    { serial = d2.item.metadata.serial })
                check('T18d item-removed', stillHave == nil, '')
                local ok5, err5 = KTRS.Tx.RetrieveWeapon(src, uid4,
                    ('kmqtest_%d_e'):format(os.time()))
                check('T18d retrieve', ok5 == true, 'err=' .. tostring(err5))
                local back = inv.FindItem(src, 'weapon_pistol',
                    { serial = d2.item.metadata.serial })
                check('T18d item-returned-once', back ~= nil, '')
            end
        else
            results[#results + 1] = 'T18d SKIPPED (no weapon_pistol in inventory / no bridge)'
        end

        for _, r in ipairs(results) do say(src, r) end
        SaveResourceFile(GetCurrentResourceName(), 'tests/weapon_tx_results.json',
            json.encode({ at = os.date('!%Y-%m-%dT%H:%M:%SZ'), results = results }), -1)
        say(src, 'saved tests/weapon_tx_results.json')
    end)
end, true)

-- restart persistence helper: dump registry counts before/after `restart`
RegisterCommand('kmq:registry_stats', function(src)
    if not allowed(src) then return end
    local n = 0
    local perScope = {}
    local rows = MySQL.query.await([[SELECT scope_type, scope_id, COUNT(*) c
        FROM kotzu_displays WHERE deleted_at IS NULL GROUP BY scope_type, scope_id]]) or {}
    for _, r in ipairs(rows) do
        n = n + r.c
        perScope[#perScope + 1] = ('%s/%s=%d'):format(r.scope_type, tostring(r.scope_id), r.c)
    end
    say(src, ('%d live display(s): %s'):format(n, table.concat(perScope, ' ')))
end, true)
