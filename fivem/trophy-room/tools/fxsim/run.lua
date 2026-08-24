-- FXServer simulator driver: loads the REAL trophy-room server scripts against
-- a REAL MariaDB and exercises the RPC surface end to end.
--
-- Usage:  cd tools/fxsim && lua5.4 run.lua
-- Env:    FXSIM_MYSQL_SOCKET (default /run/mysqld/mysqld.sock)
--         FXSIM_MYSQL_DB     (default ktr_sim; DROPPED AND RECREATED)

package.path = './?.lua;' .. package.path

-- fresh database
local SOCKET = os.getenv('FXSIM_MYSQL_SOCKET') or '/run/mysqld/mysqld.sock'
local DB = os.getenv('FXSIM_MYSQL_DB') or 'ktr_sim'
assert(os.execute(('mariadb --socket=%s -e "DROP DATABASE IF EXISTS %s; CREATE DATABASE %s"')
    :format(SOCKET, DB, DB)), 'cannot prepare database')

local SIM = require('shim')
require('mysql_shim')

-- ------------------------------------------------------------------ loading
local ROOT = '../../resources/[kotzu]'
SIM.RegisterResource('kotzu_trophy_room', ROOT .. '/kotzu_trophy_room')
SIM.RegisterResource('kotzu_mannequin_assets', ROOT .. '/kotzu_mannequin_assets')

-- Fake Qbox core so the whole suite exercises the qbox framework bridge.
-- Export surface mirrors the real qbx_core (GetPlayer/HasPermission/Notify).
SIM.RegisterResource('qbx_core', '.')
SIM.RegisterExternalExports('qbx_core', {
    GetPlayer = function(src)
        if not SIM.players[src] then return nil end
        return { PlayerData = {
            citizenid = ('QBX%05d'):format(src),
            charinfo = { firstname = 'Sim', lastname = 'Qbx' .. src },
            job = { name = 'police', grade = { name = 'officer', level = 2 } },
        } }
    end,
    HasPermission = function(_, _) return false end,
    Notify = function(src, text, _)
        table.insert(SIM.clientEvents, { name = 'qbx:notify', src = src, args = { text } })
    end,
})

SIM.LoadScripts('kotzu_trophy_room', ROOT .. '/kotzu_trophy_room', {
    -- shared (fxmanifest order)
    'shared/constants.lua', 'shared/config.lua', 'shared/schemas.lua',
    'shared/locales.lua', 'shared/rpc.lua', 'bridge/init.lua',
    -- server scripts (oxmysql replaced by mysql_shim)
    'bridge/framework/qbox.lua',
    'bridge/framework/qbcore.lua', 'bridge/framework/standalone.lua',
    'bridge/inventory/qb.lua', 'bridge/inventory/ox.lua', 'bridge/inventory/fallback.lua',
    'bridge/housing/generic.lua',
    'server/repository.lua', 'server/permissions.lua', 'server/validation.lua',
    'server/ratelimit.lua', 'server/transactions.lua', 'server/migrations.lua',
    'server/main.lua', 'tests/server_harness.lua',
})
SIM.Drain() -- migrations run -> migrationsReady -> Repo.LoadAll + RecoverStranded

-- ------------------------------------------------------------------ helpers
local failures, passes = {}, 0
local function check(name, cond, detail)
    if cond then
        passes = passes + 1
        print(('  PASS %s'):format(name))
    else
        failures[#failures + 1] = name
        print(('  FAIL %s — %s'):format(name, detail or ''))
    end
end

local reqCounter = 0
local function rpc(src, name, args)
    reqCounter = reqCounter + 1
    local reqId = 'req_' .. reqCounter
    SIM.FromClient('kotzu_trophy:rpc:request', src, name, reqId, args)
    SIM.Drain()
    for i = #SIM.clientEvents, 1, -1 do
        local e = SIM.clientEvents[i]
        if e.name == 'kotzu_trophy:rpc:response' and e.src == src and e.args[1] == reqId then
            return e.args[2], e.args[3] -- ok, payload
        end
    end
    return nil, 'no response'
end

local C = KTR.Const

-- players: 1 owner, 2 visitor, 3 admin, 4 rate-limit probe
SIM.AddPlayer(1, { license = 'license:owner1' })
SIM.AddPlayer(2, { license = 'license:visitor2' })
SIM.AddPlayer(3, { license = 'license:admin3', aces = { [KTR.Config.AdminAce] = true } })
SIM.AddPlayer(4, { license = 'license:probe4' })

print('== S1 boot: migrations + repository ==')
check('S1 repo ready', KTRS.Repo.Ready())
check('S1 migrations recorded',
    MySQL.scalar.await('SELECT COUNT(*) FROM kotzu_schema_migrations') == 4)

print('== S2 place bare mannequin (world scope) ==')
local ok2, res2 = rpc(1, 'displays:place', { display = {
    displayType = C.DisplayType.MANNEQUIN, scopeType = C.ScopeType.WORLD,
    transform = { x = 10.0, y = 20.0, z = 30.0, heading = 90.0 },
    gender = 'male', poseId = 'neutral', platform = 'none', label = 'Sim Test',
} })
check('S2 place ok', ok2 == true and type(res2) == 'table' and res2.uid ~= nil,
    json.encode(res2))
local uid = ok2 and res2.uid or nil
check('S2 row persisted', uid and MySQL.scalar.await(
    'SELECT COUNT(*) FROM kotzu_displays WHERE uid = ? AND deleted_at IS NULL', { uid }) == 1)
check('S2 broadcast upsert sent',
    SIM.LastClientEvent('kotzu_trophy:display:upsert') ~= nil)
check('S2 owner not leaked in broadcast', (function()
    local e = SIM.LastClientEvent('kotzu_trophy:display:upsert')
    return e and e.args[1].owner == nil and e.args[1].uid == uid
end)())

print('== S3 outfit vs manifest v0 -> MANIFEST_NOT_BUILT ==')
local ok3, err3 = rpc(1, 'displays:place', { display = {
    displayType = C.DisplayType.MANNEQUIN, scopeType = C.ScopeType.WORLD,
    transform = { x = 10.0, y = 20.0, z = 30.0, heading = 0.0 },
    gender = 'male',
    outfit = {
        schema = C.OUTFIT_SCHEMA, gender = 'male', model = 'mp_m_freemode_01',
        components = { ['11'] = { collection = '', drawable = 5, texture = 0, palette = 0 } },
        props = {},
    },
} })
check('S3 refused with MANIFEST_NOT_BUILT', ok3 == false and err3 == C.Err.MANIFEST_NOT_BUILT,
    tostring(err3))

print('== S4 permissions: visitor cannot update/delete; admin can ==')
local ok4, err4 = rpc(2, 'displays:update',
    { uid = uid, patch = { label = 'hacked' } })
check('S4 visitor update denied', ok4 == false and err4 == C.Err.NOT_ALLOWED, tostring(err4))
local ok4b, err4b = rpc(2, 'displays:delete', { uid = uid })
check('S4 visitor delete denied', ok4b == false and err4b == C.Err.NOT_ALLOWED, tostring(err4b))
local ok4c = rpc(3, 'displays:update', { uid = uid, patch = { label = 'Admin Renamed' } })
check('S4 admin update allowed', ok4c == true)
local caps2 = select(2, rpc(2, 'displays:capabilities', { uid = uid }))
check('S4 visitor caps shape', caps2 and caps2.manage == false and caps2.tryOn == true,
    json.encode(caps2 or {}))

print('== S5 bad input rejected ==')
local ok5, err5 = rpc(1, 'displays:place', { display = {
    displayType = 'nonsense', scopeType = C.ScopeType.WORLD,
    transform = { x = 0.0, y = 0.0, z = 0.0, heading = 0.0 },
} })
check('S5 bad type', ok5 == false and err5 == C.Err.BAD_INPUT, tostring(err5))
local ok5b, err5b = rpc(1, 'displays:place', { display = {
    displayType = C.DisplayType.MANNEQUIN, scopeType = C.ScopeType.WORLD,
    transform = { x = 0.0 / 0.0, y = 0.0, z = 0.0, heading = 0.0 }, gender = 'male',
} })
check('S5 NaN transform', ok5b == false and err5b == C.Err.BAD_INPUT, tostring(err5b))
local ok5c, err5c = rpc(1, 'displays:update', { uid = uid, patch = { poseId = 'not_a_pose' } })
check('S5 pose whitelist', ok5c == false and err5c == C.Err.BAD_INPUT, tostring(err5c))

print('== S6 rate limiting ==')
local limited = false
for _ = 1, KTR.Config.RateLimit.place + 2 do
    local okL, errL = rpc(4, 'displays:place', { display = {
        displayType = C.DisplayType.MANNEQUIN, scopeType = C.ScopeType.WORLD,
        transform = { x = 1.0, y = 1.0, z = 1.0, heading = 0.0 }, gender = 'male',
    } })
    if okL == false and errL == C.Err.RATE_LIMITED then limited = true end
end
check('S6 place rate-limited within a minute', limited)

print('== S7 weapon transaction (mock inventory) ==')
local mockItems = { [1] = { { name = 'weapon_pistol', slot = 1,
                              metadata = { serial = 'SER123' }, count = 1 } } }
local function findIn(src, name, meta)
    for _, it in ipairs(mockItems[src] or {}) do
        if it.name == name then
            local okm = true
            for k, v in pairs(meta or {}) do
                if it.metadata[k] ~= v then okm = false end
            end
            if okm then return { name = it.name, slot = it.slot,
                                 metadata = it.metadata, count = it.count } end
        end
    end
    return nil
end
KTR.Bridge.Register('inventory', 'mock', 99, {
    detect = function() return true end,
    Functional = function() return true end,
    FindItem = findIn,
    RemoveItem = function(src, name, slot)
        local list = mockItems[src] or {}
        for i, it in ipairs(list) do
            if it.name == name and it.slot == slot then table.remove(list, i) return true end
        end
        return false
    end,
    AddItem = function(src, name, metadata)
        mockItems[src] = mockItems[src] or {}
        table.insert(mockItems[src], { name = name, slot = #mockItems[src] + 10,
                                       metadata = metadata or {}, count = 1 })
        return true
    end,
})
KTR.Bridge._resolved.inventory = nil -- re-resolve to pick the mock

local wDisplay = {
    displayType = C.DisplayType.WEAPON_STAND, scopeType = C.ScopeType.WORLD,
    transform = { x = 5.0, y = 5.0, z = 5.0, heading = 0.0 },
    item = { name = 'weapon_pistol', metadata = {} },
}
local ok7, res7 = rpc(1, 'displays:place', { display = wDisplay, idKey = 'simkey_place_1' })
check('S7 weapon place ok', ok7 == true and res7.uid ~= nil, json.encode(res7))
local wUid = ok7 and res7.uid or nil
check('S7 item removed from inventory', findIn(1, 'weapon_pistol') == nil)
check('S7 metadata authoritative (serial persisted)', wUid and (MySQL.scalar.await(
    'SELECT item_metadata FROM kotzu_displays WHERE uid = ?', { wUid }) or ''):find('SER123') ~= nil)

-- replay same idempotency key: must return SAME uid, not double-execute
local ok7b, res7b = rpc(1, 'displays:place', { display = wDisplay, idKey = 'simkey_place_1' })
check('S7 idempotent replay returns same uid',
    ok7b == true and res7b.uid == wUid, json.encode(res7b or err7b or {}))
check('S7 no duplicate rows', MySQL.scalar.await(
    "SELECT COUNT(*) FROM kotzu_displays WHERE item_name = 'weapon_pistol' AND deleted_at IS NULL") == 1)

local ok7c = rpc(1, 'weapons:retrieve', { uid = wUid, idKey = 'simkey_retr_1' })
check('S7 retrieve ok', ok7c == true)
check('S7 item back exactly once', #(mockItems[1] or {}) == 1
    and mockItems[1][1].metadata.serial == 'SER123')
local ok7d, err7d = rpc(1, 'weapons:retrieve', { uid = wUid, idKey = 'simkey_retr_2' })
check('S7 second retrieve refused', ok7d == false, tostring(err7d))
check('S7 no item duplication', #(mockItems[1] or {}) == 1)

print('== S8 missing item -> ITEM_MISSING, lock closed ==')
local ok8, err8 = rpc(1, 'displays:place', { display = {
    displayType = C.DisplayType.WEAPON_STAND, scopeType = C.ScopeType.WORLD,
    transform = { x = 5.0, y = 5.0, z = 5.0, heading = 0.0 },
    item = { name = 'weapon_never_owned', metadata = {} },
}, idKey = 'simkey_missing_1' })
check('S8 ITEM_MISSING', ok8 == false and err8 == C.Err.ITEM_MISSING, tostring(err8))
check('S8 lock failed-closed', MySQL.scalar.await(
    "SELECT state FROM kotzu_tx_locks WHERE idempotency_key = 'simkey_missing_1'") == 'failed')

print('== S9 stranded-lock recovery ==')
MySQL.update.await([[INSERT INTO kotzu_tx_locks
    (idempotency_key, action, state, actor_citizenid, item_name)
    VALUES ('simkey_stranded', 'place', 'item_removed', 'license:owner1', 'weapon_pistol')]])
KTRS.Tx.RecoverStranded()
SIM.Drain()
check('S9 stranded place recovered', MySQL.scalar.await(
    "SELECT state FROM kotzu_tx_locks WHERE idempotency_key = 'simkey_stranded'") == 'recovered')
check('S9 recovery credit audited', MySQL.scalar.await(
    "SELECT COUNT(*) FROM kotzu_display_audit WHERE action = 'weapon_recovery_credit'") == 1)

print('== S10 delete + scope listing ==')
local ok10 = rpc(1, 'displays:delete', { uid = uid })
check('S10 owner delete ok', ok10 == true)
local ok10b, err10b = rpc(1, 'displays:delete', { uid = uid })
check('S10 double delete NOT_FOUND', ok10b == false and err10b == C.Err.NOT_FOUND, tostring(err10b))
local okL, list = rpc(2, 'displays:listScope', { scopeType = C.ScopeType.WORLD })
check('S10 listScope works', okL == true and type(list) == 'table')

print('== S11 db consistency ==')
local okV, resV = rpc(3, 'admin:validateDb', {})
check('S11 validateDb clean', okV == true and #resV.problems == 0,
    okV and json.encode(resV.problems) or tostring(resV))

print('== S12 Qbox framework bridge + illenium saved outfits ==')
local fw = KTR.Bridge.Get('framework')
check('S12 qbox bridge selected', fw ~= nil and fw.__name == 'qbox',
    fw and fw.__name or 'none')
local ident = KTRS.Perms.Identity(1)
check('S12 identity from qbx PlayerData', ident ~= nil
    and ident.citizenid == 'QBX00001' and ident.job == 'police' and ident.grade == 2,
    json.encode(ident or {}))

-- illenium-appearance player_outfits table (as shipped in its sql/)
MySQL.query.await([[CREATE TABLE IF NOT EXISTS `player_outfits` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `citizenid` varchar(50) DEFAULT NULL,
    `outfitname` varchar(50) NOT NULL DEFAULT '0',
    `model` varchar(50) DEFAULT NULL,
    `props` varchar(1000) DEFAULT NULL,
    `components` varchar(1500) DEFAULT NULL,
    PRIMARY KEY (`id`))]])
MySQL.update.await(
    "INSERT INTO player_outfits (citizenid, outfitname, model, components, props) VALUES (?, ?, ?, ?, ?)",
    { 'QBX00001', 'patrol', 'mp_m_freemode_01',
      '[{"component_id":11,"drawable":55,"texture":0}]',
      '[{"prop_id":0,"drawable":12,"texture":0}]' })

local okS, listRes = rpc(1, 'outfit:savedList', {})
check('S12 savedList returns the outfit', okS == true and listRes.outfits
    and #listRes.outfits == 1 and listRes.outfits[1].label == 'patrol',
    json.encode(listRes or {}))
local outfitId = okS and listRes.outfits and listRes.outfits[1] and listRes.outfits[1].id
local okG, getRes = rpc(1, 'outfit:savedGet', { id = outfitId })
check('S12 savedGet returns payload', okG == true and getRes.model == 'mp_m_freemode_01'
    and getRes.components[1].component_id == 11 and getRes.components[1].drawable == 55,
    json.encode(getRes or {}))
local okG2, errG2 = rpc(2, 'outfit:savedGet', { id = outfitId })
check('S12 other player cannot read it', okG2 == false, tostring(errG2))

print('== S13 case styles + auto-rotate settings ==')
mockItems[1] = { { name = 'weapon_carbinerifle', slot = 2,
                   metadata = { serial = 'SER777' }, count = 1 } }
local ok13, res13 = rpc(1, 'displays:place', { display = {
    displayType = C.DisplayType.WEAPON_CASE, scopeType = C.ScopeType.WORLD,
    transform = { x = 6.0, y = 6.0, z = 6.0, heading = 0.0 },
    caseStyle = 'horizontal',
    settings = { rotate = { enabled = true, speed = 15.0 } },
    item = { name = 'weapon_carbinerifle', metadata = {} },
}, idKey = 'simkey_case_1' })
check('S13 case place ok', ok13 == true and res13.uid ~= nil, json.encode(res13))
local cUid = ok13 and res13.uid or nil
check('S13 case style + settings persisted', cUid and (function()
    local row = MySQL.single.await(
        'SELECT case_style, settings FROM kotzu_displays WHERE uid = ?', { cUid })
    return row and row.case_style == 'horizontal'
        and (row.settings or ''):find('"enabled":true') ~= nil
end)() == true)

local ok13b, err13b = rpc(1, 'displays:update', { uid = cUid, patch = {
    settings = { rotate = { enabled = false, speed = 30.0 } } } })
check('S13 settings update ok', ok13b == true, tostring(err13b))
check('S13 settings updated in db', cUid and (MySQL.scalar.await(
    'SELECT settings FROM kotzu_displays WHERE uid = ?', { cUid }) or '')
    :find('"enabled":false') ~= nil)

local ok13c, err13c = rpc(1, 'displays:update', { uid = cUid, patch = {
    settings = { rotate = { enabled = true, speed = 9999 } } } })
check('S13 out-of-range speed rejected', ok13c == false and err13c == C.Err.BAD_INPUT,
    tostring(err13c))
local ok13d, err13d = rpc(1, 'displays:place', { display = {
    displayType = C.DisplayType.WEAPON_CASE, scopeType = C.ScopeType.WORLD,
    transform = { x = 6.0, y = 6.0, z = 6.0, heading = 0.0 },
    caseStyle = 'pyramid',
    item = { name = 'weapon_carbinerifle', metadata = {} },
}, idKey = 'simkey_case_2' })
check('S13 unknown case style rejected', ok13d == false and err13d == C.Err.BAD_INPUT,
    tostring(err13d))

print('== S14 anti-dupe: weapon serial uniqueness across displays ==')
-- fresh player (no rate-limit history from earlier scenarios)
SIM.AddPlayer(5, { license = 'license:dupe5' })
mockItems[5] = {
    { name = 'weapon_pistol50', slot = 3, metadata = { serial = 'DUPE-1' }, count = 1 },
    { name = 'weapon_pistol50', slot = 4, metadata = { serial = 'DUPE-1' }, count = 1 },
}
local dispA = {
    displayType = C.DisplayType.WEAPON_STAND, scopeType = C.ScopeType.WORLD,
    transform = { x = 7.0, y = 7.0, z = 7.0, heading = 0.0 },
    item = { name = 'weapon_pistol50', metadata = {} },
}
local okA, resA = rpc(5, 'displays:place', { display = dispA, idKey = 'dupetest_a' })
check('S14 first place ok', okA == true and resA.uid ~= nil, json.encode(resA))
local dupUid = okA and resA.uid or nil

local okB, errB = rpc(5, 'displays:place', {
    display = {
        displayType = C.DisplayType.WEAPON_STAND, scopeType = C.ScopeType.WORLD,
        transform = { x = 7.5, y = 7.0, z = 7.0, heading = 0.0 },
        item = { name = 'weapon_pistol50', metadata = {} },
    }, idKey = 'dupetest_b' })
check('S14 second place (same serial) refused DUPLICATE',
    okB == false and errB == C.Err.DUPLICATE, tostring(errB))
check('S14 only one live display holds the serial', MySQL.scalar.await(
    "SELECT COUNT(*) FROM kotzu_displays WHERE item_name='weapon_pistol50' AND deleted_at IS NULL") == 1)
check('S14 dupe attempt audited', MySQL.scalar.await(
    "SELECT COUNT(*) FROM kotzu_display_audit WHERE action='weapon_dupe_blocked'") >= 1)

-- after retrieving, the serial is freed and can be re-placed (not a permanent ban)
local okR = rpc(5, 'weapons:retrieve', { uid = dupUid, idKey = 'dupetest_r' })
check('S14 retrieve frees the serial', okR == true)
local okC = rpc(5, 'displays:place', { display = dispA, idKey = 'dupetest_c' })
check('S14 re-place after retrieve allowed', okC == true, tostring(okC))

check('S14 per-player inflight lock exists', type(KTRS.Tx._inflight) == 'table')

print('== S15 clothing has no economy dupe (outfit RPCs never touch inventory) ==')
-- capturing/try-on is cosmetic: prove the outfit RPCs return data only and the
-- inventory is untouched by an outfit round-trip.
local invBefore = #(mockItems[5] or {})
rpc(5, 'outfit:savedList', {})
rpc(5, 'outfit:forTryOn', { uid = dupUid }) -- dupUid now deleted -> NOT_FOUND, still no item change
check('S15 inventory unchanged by outfit RPCs', #(mockItems[5] or {}) == invBefore)

print('')
print(('RESULT: %d passed, %d failed'):format(passes, #failures))
for _, f in ipairs(failures) do print('  FAILED: ' .. f) end
os.exit(#failures == 0 and 0 or 1)
