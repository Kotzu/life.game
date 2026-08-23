--[[ Server entry: RPC surface, scope-filtered broadcasts, lifecycle. ]]

local C = KTR.Const
local RPC = KTR.RPC

AddEventHandler('kotzu_trophy:server:migrationsReady', function()
    KTRS.Repo.LoadAll()
    KTRS.Tx.RecoverStranded()
end)

-- ------------------------------------------------------------- broadcasting

local function playersInBucket(bucket)
    local out = {}
    for _, sid in ipairs(GetPlayers()) do
        local src = tonumber(sid)
        if GetPlayerRoutingBucket(src) == bucket then out[#out + 1] = src end
    end
    return out
end

local function publicView(d)
    -- what clients need to render; permissions stay server-side except flags
    return {
        uid = d.uid, displayType = d.displayType,
        scopeType = d.scopeType, scopeId = d.scopeId, bucket = d.bucket,
        transform = d.transform, gender = d.gender, outfit = d.outfit,
        poseId = d.poseId, platform = d.platform,
        caseStyle = d.caseStyle, settings = d.settings,
        item = d.item and { name = d.item.name, metadata = {
            serial = d.item.metadata and d.item.metadata.serial or nil,
            tint = d.item.metadata and d.item.metadata.tint or nil,
            components = d.item.metadata and d.item.metadata.components or nil,
            rarity = d.item.metadata and d.item.metadata.rarity or nil,
            achievement = d.item.metadata and d.item.metadata.achievement or nil,
        } } or nil,
        label = d.label, description = d.description,
        manifestVersion = d.manifestVersion,
    }
end

local function broadcastUpsert(d)
    for _, src in ipairs(playersInBucket(d.bucket)) do
        TriggerClientEvent('kotzu_trophy:display:upsert', src, publicView(d))
    end
end

local function broadcastDelete(d)
    for _, src in ipairs(playersInBucket(d.bucket)) do
        TriggerClientEvent('kotzu_trophy:display:delete', src, d.uid)
    end
end

-- ------------------------------------------------------------------ queries

RPC.Register('displays:listScope', function(src, args)
    if not KTRS.RateLimit.Check(src, 'query') then return nil, C.Err.RATE_LIMITED end
    if not KTRS.Repo.Ready() then return {} end
    if type(args) ~= 'table' then return nil, C.Err.BAD_INPUT end
    local scopeType = args.scopeType
    local scopeId = args.scopeId
    if scopeType ~= C.ScopeType.WORLD then
        if type(scopeId) ~= 'string' then return nil, C.Err.BAD_INPUT end
        local h = KTR.Bridge.Get('housing')
        local res = h and h.ResolveScope(src, scopeType, scopeId)
        if not res or not res.allowed then return nil, C.Err.NOT_ALLOWED end
    else
        scopeId = nil
    end
    local bucket = GetPlayerRoutingBucket(src)
    local out = {}
    for _, d in ipairs(KTRS.Repo.ListForScope(scopeType, scopeId, bucket)) do
        out[#out + 1] = publicView(d)
    end
    return out
end)

RPC.Register('displays:capabilities', function(src, args)
    if type(args) ~= 'table' or type(args.uid) ~= 'string' then return nil, C.Err.BAD_INPUT end
    local d = KTRS.Repo.Get(args.uid)
    if not d then return nil, C.Err.NOT_FOUND end
    return KTRS.Perms.Capabilities(src, d)
end)

RPC.Register('bridges:describe', function(src)
    local desc = KTR.Bridge.Describe()
    desc.inventoryFunctional = (function()
        local i = KTR.Bridge.Get('inventory')
        return i and i.Functional() or false
    end)()
    return desc
end)

-- ---------------------------------------------------------------- placement

RPC.Register('displays:place', function(src, args)
    if not KTRS.RateLimit.Check(src, 'place') then return nil, C.Err.RATE_LIMITED end
    if type(args) ~= 'table' or type(args.display) ~= 'table' then
        return nil, C.Err.BAD_INPUT
    end
    local d = args.display
    local id = KTRS.Perms.Identity(src)
    if not id then return nil, C.Err.NOT_ALLOWED end

    local okScope, resOrErr = KTRS.Perms.CanPlaceInScope(src, d.scopeType, d.scopeId)
    if not okScope then return nil, resOrErr end

    local ok, errCode, detail = KTRS.Validate.DisplayInput(src, d)
    if not ok then
        print(('[kotzu_trophy] place rejected for %s: %s %s'):format(id.citizenid, errCode, detail or ''))
        return nil, errCode
    end

    if KTRS.Repo.CountForScope(d.scopeType, d.scopeId) >= KTR.Config.Limits.DisplaysPerScope
        or KTRS.Repo.CountForOwner(id.citizenid) >= KTR.Config.Limits.DisplaysPerOwner then
        return nil, C.Err.LIMIT_REACHED
    end

    d.owner = id.citizenid
    d.permissions = type(d.permissions) == 'table' and d.permissions or {}

    local uid
    if d.displayType:find('^weapon_') then
        local wUid, wErr = KTRS.Tx.PlaceWeapon(src, d, args.idKey)
        if not wUid then return nil, wErr end
        uid = wUid
    else
        uid = KTRS.Repo.Create(d)
        if not uid then return nil, C.Err.INTERNAL end
        KTRS.Repo.Audit(uid, id.citizenid, 'placed', { type = d.displayType })
    end

    broadcastUpsert(KTRS.Repo.Get(uid))
    return { uid = uid }
end)

RPC.Register('displays:update', function(src, args)
    if not KTRS.RateLimit.Check(src, 'update') then return nil, C.Err.RATE_LIMITED end
    if type(args) ~= 'table' or type(args.uid) ~= 'string' or type(args.patch) ~= 'table' then
        return nil, C.Err.BAD_INPUT
    end
    local d = KTRS.Repo.Get(args.uid)
    if not d then return nil, C.Err.NOT_FOUND end
    local caps = KTRS.Perms.Capabilities(src, d)
    if not caps.manage then return nil, C.Err.NOT_ALLOWED end

    -- validate the patch through the same schema path as placement
    local merged = {
        displayType = d.displayType, scopeType = d.scopeType, scopeId = d.scopeId,
        transform = args.patch.transform or d.transform,
        gender = d.gender,
        outfit = args.patch.outfit or d.outfit,
        poseId = args.patch.poseId or d.poseId,
        platform = args.patch.platform or d.platform,
        caseStyle = args.patch.caseStyle or d.caseStyle,
        settings = args.patch.settings or d.settings,
        label = args.patch.label or d.label,
        description = args.patch.description or d.description,
        item = d.item,
    }
    local ok, errCode = KTRS.Validate.DisplayInput(src, merged)
    if not ok then return nil, errCode end

    -- only allow known-safe fields through
    local patch = {}
    for _, k in ipairs({ 'transform', 'outfit', 'poseId', 'platform', 'caseStyle',
                         'settings', 'label', 'description', 'permissions' }) do
        if args.patch[k] ~= nil then patch[k] = args.patch[k] end
    end
    if patch.outfit then patch.manifestVersion = merged.manifestVersion or d.manifestVersion end

    local updated = KTRS.Repo.Update(args.uid, patch)
    if not updated then return nil, C.Err.INTERNAL end
    local id = KTRS.Perms.Identity(src)
    KTRS.Repo.Audit(args.uid, id and id.citizenid or '?', 'updated',
        { fields = (function() local f = {} for k in pairs(patch) do f[#f + 1] = k end return f end)() })
    broadcastUpsert(updated)
    return { uid = args.uid }
end)

RPC.Register('displays:delete', function(src, args)
    if not KTRS.RateLimit.Check(src, 'delete') then return nil, C.Err.RATE_LIMITED end
    if type(args) ~= 'table' or type(args.uid) ~= 'string' then return nil, C.Err.BAD_INPUT end
    local d = KTRS.Repo.Get(args.uid)
    if not d then return nil, C.Err.NOT_FOUND end
    local caps = KTRS.Perms.Capabilities(src, d)
    if not caps.remove then return nil, C.Err.NOT_ALLOWED end
    if d.displayType:find('^weapon_') then
        -- weapon displays must go through the retrieval transaction
        return nil, C.Err.BAD_INPUT
    end
    if not KTRS.Repo.Delete(args.uid) then return nil, C.Err.NOT_FOUND end
    local id = KTRS.Perms.Identity(src)
    KTRS.Repo.Audit(args.uid, id and id.citizenid or '?', 'deleted', nil)
    broadcastDelete(d)
    return { uid = args.uid }
end)

-- ------------------------------------------------------------------ weapons

RPC.Register('weapons:retrieve', function(src, args)
    if not KTRS.RateLimit.Check(src, 'weapon_tx') then return nil, C.Err.RATE_LIMITED end
    if type(args) ~= 'table' or type(args.uid) ~= 'string' then return nil, C.Err.BAD_INPUT end
    local d = KTRS.Repo.Get(args.uid)
    local ok, err = KTRS.Tx.RetrieveWeapon(src, args.uid, args.idKey)
    if not ok then return nil, err end
    if d then broadcastDelete(d) end
    return { uid = args.uid }
end)

-- ------------------------------------------------------------------- outfits

RPC.Register('outfit:forTryOn', function(src, args)
    if not KTRS.RateLimit.Check(src, 'preview') then return nil, C.Err.RATE_LIMITED end
    if type(args) ~= 'table' or type(args.uid) ~= 'string' then return nil, C.Err.BAD_INPUT end
    local d = KTRS.Repo.Get(args.uid)
    if not d or not d.outfit then return nil, C.Err.NOT_FOUND end
    local caps = KTRS.Perms.Capabilities(src, d)
    if not caps.tryOn then return nil, C.Err.NOT_ALLOWED end
    return { outfit = d.outfit, seconds = KTR.Config.Interaction.TryOnSeconds }
end)

-- Saved outfits from illenium-appearance's player_outfits table (Qbox setups).
-- Feature-detected: if the table doesn't exist the RPCs answer with an explicit
-- 'unsupported' instead of erroring.

-- Only a POSITIVE probe is cached: a missing table (illenium not yet started)
-- or a transient DB error must not disable the feature until restart.
local savedOutfitsAvailable = false
local function outfitsTableExists()
    if savedOutfitsAvailable then return true end
    local ok, res = pcall(function()
        return MySQL.scalar.await("SHOW TABLES LIKE 'player_outfits'")
    end)
    if ok and res ~= nil then savedOutfitsAvailable = true end
    return savedOutfitsAvailable
end

RPC.Register('outfit:savedList', function(src)
    if not KTRS.RateLimit.Check(src, 'query') then return nil, C.Err.RATE_LIMITED end
    if not outfitsTableExists() then return { outfits = nil, unsupported = true } end
    local id = KTRS.Perms.Identity(src)
    if not id then return nil, C.Err.NOT_ALLOWED end
    local rows = MySQL.query.await(
        'SELECT id, outfitname, model FROM player_outfits WHERE citizenid = ? LIMIT 100',
        { id.citizenid }) or {}
    local outfits = {}
    for _, r in ipairs(rows) do
        outfits[#outfits + 1] = { id = r.id, label = r.outfitname, model = r.model }
    end
    return { outfits = outfits }
end)

RPC.Register('outfit:savedGet', function(src, args)
    if not KTRS.RateLimit.Check(src, 'query') then return nil, C.Err.RATE_LIMITED end
    if not outfitsTableExists() then return nil, C.Err.BAD_INPUT end
    if type(args) ~= 'table' or tonumber(args.id) == nil then return nil, C.Err.BAD_INPUT end
    local id = KTRS.Perms.Identity(src)
    if not id then return nil, C.Err.NOT_ALLOWED end
    -- ownership enforced in the WHERE clause: players read only their outfits
    local row = MySQL.single.await(
        'SELECT outfitname, model, components, props FROM player_outfits WHERE id = ? AND citizenid = ?',
        { tonumber(args.id), id.citizenid })
    if not row then return nil, C.Err.NOT_FOUND end
    local okC, components = pcall(json.decode, row.components or '[]')
    local okP, props = pcall(json.decode, row.props or '[]')
    if not okC or type(components) ~= 'table' then return nil, C.Err.OUTFIT_INVALID end
    return {
        label = row.outfitname,
        model = row.model,
        components = components,
        props = okP and props or {},
    }
end)

-- -------------------------------------------------------------------- admin

RPC.Register('admin:reloadManifest', function(src)
    if not KTRS.Perms.IsAdmin(src) then return nil, C.Err.NOT_ALLOWED end
    local m = KTRS.Validate.ReloadManifest()
    return { version = m and m.version or 0 }
end)

RPC.Register('admin:validateDb', function(src)
    if not KTRS.Perms.IsAdmin(src) then return nil, C.Err.NOT_ALLOWED end
    return { problems = KTRS.Repo.ValidateDb() }
end)
