--[[
    Repository: persistence + in-memory registry of live displays.
    The cache is loaded once after migrations and kept authoritative by the
    mutation functions; clients only ever see rows for their scope + bucket.
]]

KTRS = KTRS or {}
KTRS.Repo = {}
local Repo = KTRS.Repo

local cache = {}      -- uid -> display record (decoded)
local cacheReady = false

local function uuid()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return (template:gsub('[xy]', function(c)
        local v = (c == 'x') and math.random(0, 15) or math.random(8, 11)
        return ('%x'):format(v)
    end))
end

local function rowToRecord(row)
    return {
        uid = row.uid,
        owner = row.owner_citizenid,
        displayType = row.display_type,
        scopeType = row.scope_type,
        scopeId = row.scope_id,
        bucket = row.routing_bucket,
        transform = { x = row.loc_x, y = row.loc_y, z = row.loc_z, heading = row.loc_heading },
        gender = row.gender,
        outfit = row.outfit and json.decode(row.outfit) or nil,
        poseId = row.pose_id,
        platform = row.platform,
        item = row.item_name and {
            name = row.item_name,
            metadata = row.item_metadata and json.decode(row.item_metadata) or {},
        } or nil,
        label = row.label,
        description = row.description,
        permissions = row.permissions and json.decode(row.permissions) or {},
        manifestVersion = row.manifest_version,
        createdAt = row.created_at,
        updatedAt = row.updated_at,
    }
end

function Repo.LoadAll()
    local rows = MySQL.query.await(
        'SELECT * FROM kotzu_displays WHERE deleted_at IS NULL') or {}
    cache = {}
    for _, row in ipairs(rows) do
        cache[row.uid] = rowToRecord(row)
    end
    cacheReady = true
    print(('[kotzu_trophy] repository loaded %d display(s)'):format(#rows))
end

function Repo.Ready() return cacheReady end

function Repo.Get(uid) return cache[uid] end

---All live displays matching a scope+bucket (nil scopeId = world scope).
function Repo.ListForScope(scopeType, scopeId, bucket)
    local out = {}
    for _, d in pairs(cache) do
        if d.scopeType == scopeType and d.scopeId == scopeId and d.bucket == bucket then
            out[#out + 1] = d
        end
    end
    return out
end

function Repo.CountForScope(scopeType, scopeId)
    local n = 0
    for _, d in pairs(cache) do
        if d.scopeType == scopeType and d.scopeId == scopeId then n = n + 1 end
    end
    return n
end

function Repo.CountForOwner(owner)
    local n = 0
    for _, d in pairs(cache) do
        if d.owner == owner then n = n + 1 end
    end
    return n
end

---@return string|nil uid
function Repo.Create(d)
    local uid = uuid()
    local id = MySQL.insert.await([[
        INSERT INTO kotzu_displays
            (uid, owner_citizenid, display_type, scope_type, scope_id, routing_bucket,
             loc_x, loc_y, loc_z, loc_heading, gender, outfit, pose_id, platform,
             item_name, item_metadata, label, description, permissions, manifest_version)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        uid, d.owner, d.displayType, d.scopeType, d.scopeId, d.bucket,
        d.transform.x, d.transform.y, d.transform.z, d.transform.heading,
        d.gender, d.outfit and json.encode(d.outfit) or nil, d.poseId, d.platform,
        d.item and d.item.name or nil,
        d.item and json.encode(d.item.metadata or {}) or nil,
        d.label, d.description, json.encode(d.permissions or {}),
        d.manifestVersion or 0,
    })
    if not id then return nil end
    d.uid = uid
    cache[uid] = d
    return uid
end

---Patch a subset of mutable fields; returns updated record or nil.
function Repo.Update(uid, patch)
    local d = cache[uid]
    if not d then return nil end
    local sets, params = {}, {}
    local map = {
        transform = function(v)
            sets[#sets + 1] = 'loc_x = ?, loc_y = ?, loc_z = ?, loc_heading = ?'
            params[#params + 1] = v.x; params[#params + 1] = v.y
            params[#params + 1] = v.z; params[#params + 1] = v.heading
            d.transform = v
        end,
        outfit = function(v)
            sets[#sets + 1] = 'outfit = ?'
            params[#params + 1] = json.encode(v)
            d.outfit = v
        end,
        poseId = function(v) sets[#sets + 1] = 'pose_id = ?' params[#params + 1] = v d.poseId = v end,
        platform = function(v) sets[#sets + 1] = 'platform = ?' params[#params + 1] = v d.platform = v end,
        label = function(v) sets[#sets + 1] = 'label = ?' params[#params + 1] = v d.label = v end,
        description = function(v) sets[#sets + 1] = 'description = ?' params[#params + 1] = v d.description = v end,
        permissions = function(v)
            sets[#sets + 1] = 'permissions = ?'
            params[#params + 1] = json.encode(v)
            d.permissions = v
        end,
        manifestVersion = function(v) sets[#sets + 1] = 'manifest_version = ?' params[#params + 1] = v d.manifestVersion = v end,
    }
    for k, v in pairs(patch) do
        if map[k] then map[k](v) end
    end
    if #sets == 0 then return d end
    params[#params + 1] = uid
    MySQL.update.await(
        ('UPDATE kotzu_displays SET %s WHERE uid = ? AND deleted_at IS NULL')
            :format(table.concat(sets, ', ')), params)
    return d
end

---Soft delete with row-level guard; returns true only if THIS call deleted it
---(used as the retrieval transaction's lock — see transactions.lua).
function Repo.Delete(uid)
    local affected = MySQL.update.await(
        'UPDATE kotzu_displays SET deleted_at = NOW() WHERE uid = ? AND deleted_at IS NULL',
        { uid })
    if affected and affected > 0 then
        cache[uid] = nil
        return true
    end
    return false
end

---Undo a soft delete (compensation path).
function Repo.Restore(uid)
    local affected = MySQL.update.await(
        'UPDATE kotzu_displays SET deleted_at = NULL WHERE uid = ?', { uid })
    if affected and affected > 0 then
        local row = MySQL.single.await('SELECT * FROM kotzu_displays WHERE uid = ?', { uid })
        if row then cache[uid] = rowToRecord(row) end
        return true
    end
    return false
end

function Repo.Audit(uid, actor, action, detail)
    MySQL.insert('INSERT INTO kotzu_display_audit (uid, actor_citizenid, action, detail) VALUES (?, ?, ?, ?)',
        { uid, actor, action, detail and json.encode(detail) or nil })
end

---Consistency check used by /kmq:validate_db.
function Repo.ValidateDb()
    local problems = {}
    local rows = MySQL.query.await(
        'SELECT uid FROM kotzu_displays WHERE deleted_at IS NULL') or {}
    local dbSet = {}
    for _, r in ipairs(rows) do
        dbSet[r.uid] = true
        if not cache[r.uid] then
            problems[#problems + 1] = 'db row not in cache: ' .. r.uid
        end
    end
    for uid in pairs(cache) do
        if not dbSet[uid] then
            problems[#problems + 1] = 'cache entry not in db: ' .. uid
        end
    end
    local staleLocks = MySQL.query.await(
        "SELECT idempotency_key, state FROM kotzu_tx_locks WHERE state NOT IN ('done','failed','recovered') AND updated_at < NOW() - INTERVAL 5 MINUTE") or {}
    for _, l in ipairs(staleLocks) do
        problems[#problems + 1] = ('stale tx lock %s in state %s'):format(l.idempotency_key, l.state)
    end
    return problems
end
