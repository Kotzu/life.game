--[[
    Atomic weapon place/retrieve (brief §15). Duplication is prevented by:

    1. idempotency key (client-generated UUID; INSERT into kotzu_tx_locks is the
       gate — a replayed request finds the lock and returns the prior outcome);
    2. ordered state machine written BEFORE each side effect:
         placing -> item_removed -> done            (place)
         retrieving -> row_deleted -> done          (retrieve)
       so restart recovery always knows which side effect happened;
    3. row-level guards (Repo.Delete affects-rows check = the display lock);
    4. compensation on failure (item returned / row restored) + audit rows;
    5. startup recovery for locks stranded mid-flight.
]]

KTRS = KTRS or {}
KTRS.Tx = {}
local Tx = KTRS.Tx
local C = KTR.Const

local function inv() return KTR.Bridge.Get('inventory') end

local function lockInsert(key, action, actor, itemName, itemMeta)
    -- INSERT .. IGNORE via affected rows: 0 means the key already exists
    local affected = MySQL.update.await(
        'INSERT IGNORE INTO kotzu_tx_locks (idempotency_key, action, state, actor_citizenid, item_name, item_metadata) VALUES (?, ?, ?, ?, ?, ?)',
        { key, action, action == 'place' and 'placing' or 'retrieving',
          actor, itemName, itemMeta and json.encode(itemMeta) or nil })
    return affected and affected > 0
end

local function lockState(key, state, uid)
    MySQL.update.await(
        'UPDATE kotzu_tx_locks SET state = ?, uid = COALESCE(?, uid) WHERE idempotency_key = ?',
        { state, uid, key })
end

local function lockGet(key)
    return MySQL.single.await('SELECT * FROM kotzu_tx_locks WHERE idempotency_key = ?', { key })
end

local function validKey(key)
    return type(key) == 'string' and #key >= 8 and #key <= 64 and not key:find('[^%w%-_]')
end

-- ------------------------------------------------------------------- place

---@param src number player
---@param d table validated display input (weapon_* type, includes item{name, metadata})
---@param idKey string client idempotency key
---@return string|nil uid, string|nil errCode
function Tx.PlaceWeapon(src, d, idKey)
    if not validKey(idKey) then return nil, C.Err.BAD_INPUT end
    local bridge = inv()
    if not bridge or not bridge.Functional() then
        if KTR.Config.Weapons.RequireInventoryBridge then return nil, C.Err.TX_FAILED end
    end
    local id = KTRS.Perms.Identity(src)
    if not id then return nil, C.Err.NOT_ALLOWED end

    -- metadata must carry a unique identifier so the EXACT item is locked
    local meta = d.item.metadata or {}
    local uniqueId = meta.serial or meta.serie or meta.uniqueId or meta.id
    if not uniqueId then return nil, C.Err.BAD_INPUT end

    if not lockInsert(idKey, 'place', id.citizenid, d.item.name, meta) then
        -- replay: return stored outcome instead of re-executing
        local lock = lockGet(idKey)
        if lock and lock.state == 'done' then return lock.uid end
        return nil, C.Err.TX_FAILED
    end

    -- 1. the exact item must exist NOW (ownership re-checked server-side)
    local item = bridge.FindItem(src, d.item.name, meta)
    if not item then
        lockState(idKey, 'failed')
        return nil, C.Err.ITEM_MISSING
    end
    d.item.metadata = item.metadata -- authoritative copy, never client's

    -- 2. remove item, then record that fact BEFORE inserting the display
    if not bridge.RemoveItem(src, item.name, item.slot, item.metadata) then
        lockState(idKey, 'failed')
        return nil, C.Err.TX_FAILED
    end
    lockState(idKey, 'item_removed')

    -- 3. insert display row
    local uid = KTRS.Repo.Create(d)
    if not uid then
        -- compensation: give the item back
        local returned = bridge.AddItem(src, item.name, item.metadata)
        lockState(idKey, returned and 'failed' or 'failed_item_lost')
        KTRS.Repo.Audit(nil, id.citizenid, 'weapon_place_failed',
            { key = idKey, itemReturned = returned })
        return nil, C.Err.TX_FAILED
    end

    lockState(idKey, 'done', uid)
    KTRS.Repo.Audit(uid, id.citizenid, 'weapon_placed',
        { item = item.name, uniqueId = uniqueId, key = idKey })
    return uid
end

-- ----------------------------------------------------------------- retrieve

---@return boolean ok, string|nil errCode
function Tx.RetrieveWeapon(src, uid, idKey)
    if not validKey(idKey) then return false, C.Err.BAD_INPUT end
    local bridge = inv()
    if not bridge or not bridge.Functional() then return false, C.Err.TX_FAILED end
    local id = KTRS.Perms.Identity(src)
    if not id then return false, C.Err.NOT_ALLOWED end

    local display = KTRS.Repo.Get(uid)
    if not display or not display.item then return false, C.Err.NOT_FOUND end
    local caps = KTRS.Perms.Capabilities(src, display)
    if not caps.remove then return false, C.Err.NOT_ALLOWED end

    if not lockInsert(idKey, 'retrieve', id.citizenid, display.item.name, display.item.metadata) then
        local lock = lockGet(idKey)
        if lock and lock.state == 'done' then return true end
        return false, C.Err.TX_FAILED
    end

    -- 1. soft-delete is the lock: only one caller can flip deleted_at
    if not KTRS.Repo.Delete(uid) then
        lockState(idKey, 'failed')
        return false, C.Err.NOT_FOUND
    end
    lockState(idKey, 'row_deleted', uid)

    -- 2. hand the item back
    if not bridge.AddItem(src, display.item.name, display.item.metadata) then
        -- compensation: restore the display row
        KTRS.Repo.Restore(uid)
        lockState(idKey, 'failed')
        KTRS.Repo.Audit(uid, id.citizenid, 'weapon_retrieve_failed', { key = idKey })
        return false, C.Err.TX_FAILED
    end

    lockState(idKey, 'done', uid)
    KTRS.Repo.Audit(uid, id.citizenid, 'weapon_retrieved',
        { item = display.item.name, key = idKey })
    return true, nil, display
end

-- ----------------------------------------------------------------- recovery

---Startup recovery for locks stranded by a crash/restart mid-transaction.
function Tx.RecoverStranded()
    local stranded = MySQL.query.await([[
        SELECT * FROM kotzu_tx_locks
        WHERE state IN ('placing', 'retrieving', 'item_removed', 'row_deleted')
    ]]) or {}
    for _, lock in ipairs(stranded) do
        if lock.state == 'placing' or lock.state == 'retrieving' then
            -- no side effect recorded yet -> nothing happened; just close it
            lockState(lock.idempotency_key, 'failed')
        elseif lock.state == 'item_removed' then
            -- item was taken; did the display row land?
            local row = MySQL.single.await(
                'SELECT uid FROM kotzu_displays WHERE uid = ?', { lock.uid })
            if row then
                lockState(lock.idempotency_key, 'done')
            else
                -- display never persisted: the item must be returned; owner may be
                -- offline, so record a recovery credit for admin/console handling
                lockState(lock.idempotency_key, 'recovered')
                KTRS.Repo.Audit(nil, lock.actor_citizenid, 'weapon_recovery_credit', {
                    key = lock.idempotency_key, item = lock.item_name,
                    metadata = lock.item_metadata,
                    action = 'return item to player (stranded place)',
                })
                print(('[kotzu_trophy] RECOVERY: stranded place %s — item %s owed to %s (see audit)')
                    :format(lock.idempotency_key, lock.item_name, lock.actor_citizenid))
            end
        elseif lock.state == 'row_deleted' then
            -- display row deleted but item possibly not returned: restore row,
            -- which is always safe (retrieval can be retried)
            if lock.uid then KTRS.Repo.Restore(lock.uid) end
            lockState(lock.idempotency_key, 'recovered')
            KTRS.Repo.Audit(lock.uid, lock.actor_citizenid, 'weapon_retrieve_recovered',
                { key = lock.idempotency_key })
        end
    end
    if #stranded > 0 then
        print(('[kotzu_trophy] transaction recovery processed %d stranded lock(s)'):format(#stranded))
    end
end
