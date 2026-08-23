--[[
    Shared schemas: outfit payloads, display records, migrations.
    Pure Lua, used identically on client and server. Server treats every
    client payload as untrusted and runs these validators before persisting.
]]

KTR = KTR or {}
KTR.Schemas = {}
local S = KTR.Schemas
local C = KTR.Const

local function isInt(v, lo, hi)
    return type(v) == 'number' and v == math.floor(v)
        and (lo == nil or v >= lo) and (hi == nil or v <= hi)
end

local function isStr(v, maxLen)
    return type(v) == 'string' and (maxLen == nil or #v <= maxLen)
end

-- ---------------------------------------------------------------- outfits

-- Normalized outfit, schema v2 (v1 lacked collections; migrated below):
-- {
--   schema = 2,
--   gender = 'male'|'female',
--   model  = 'mp_m_freemode_01'|'mp_f_freemode_01',
--   components = { ["0"] = { collection='', drawable=0, texture=0, palette=0 }, ... },
--   props      = { ["0"] = { collection='', drawable=0, texture=0 } | { cleared=true }, ... },
--   raw = { source='rcore_clothing'|'natives'|..., data=<opaque snapshot> },
--   manifestVersion = <int>,  -- mannequin conversion mapping version used at save
-- }

function S.MigrateOutfit(outfit)
    if type(outfit) ~= 'table' then return nil, 'not a table' end
    local v = outfit.schema or 1
    while v < C.OUTFIT_SCHEMA do
        if v == 1 then
            -- v1 stored flat global indexes: components[i] = {drawable, texture}
            -- Global indexes are collection-encoded; without the game we cannot
            -- decode them offline, so v1 payloads keep drawables as base-collection
            -- best effort and are flagged for re-capture.
            local comps = {}
            for k, comp in pairs(outfit.components or {}) do
                comps[tostring(k)] = {
                    collection = '',
                    drawable = comp.drawable or comp[1] or 0,
                    texture = comp.texture or comp[2] or 0,
                    palette = comp.palette or 0,
                }
            end
            outfit.components = comps
            outfit.props = outfit.props or {}
            outfit.migratedFromV1 = true
            v = 2
        else
            return nil, ('no migration path from v%d'):format(v)
        end
        outfit.schema = v
    end
    return outfit
end

function S.ValidateOutfit(outfit)
    if type(outfit) ~= 'table' then return false, 'outfit not a table' end
    if outfit.schema ~= C.OUTFIT_SCHEMA then return false, 'wrong schema version' end
    if outfit.gender ~= C.Gender.MALE and outfit.gender ~= C.Gender.FEMALE then
        return false, 'bad gender'
    end
    if outfit.model ~= C.Model[outfit.gender] then return false, 'model/gender mismatch' end
    if type(outfit.components) ~= 'table' then return false, 'components missing' end

    local nComps = 0
    for k, comp in pairs(outfit.components) do
        nComps = nComps + 1
        if nComps > 16 then return false, 'too many components' end
        local id = tonumber(k)
        if not isInt(id, 0, 11) then return false, 'bad component id ' .. tostring(k) end
        if type(comp) ~= 'table' then return false, 'component not a table' end
        if not isStr(comp.collection, 64) then return false, 'bad collection name' end
        if comp.collection:find('[^%w_]') then return false, 'collection name has invalid chars' end
        if not isInt(comp.drawable, 0, 4096) then return false, 'bad drawable' end
        if not isInt(comp.texture, 0, 255) then return false, 'bad texture' end
        if comp.palette ~= nil and not isInt(comp.palette, 0, 255) then return false, 'bad palette' end
    end

    local nProps = 0
    for k, prop in pairs(outfit.props or {}) do
        nProps = nProps + 1
        if nProps > 10 then return false, 'too many props' end
        local id = tonumber(k)
        if not isInt(id, 0, 8) then return false, 'bad prop id ' .. tostring(k) end
        if type(prop) ~= 'table' then return false, 'prop not a table' end
        if not prop.cleared then
            if not isStr(prop.collection, 64) then return false, 'bad prop collection' end
            if prop.collection:find('[^%w_]') then return false, 'prop collection invalid chars' end
            if not isInt(prop.drawable, 0, 4096) then return false, 'bad prop drawable' end
            if not isInt(prop.texture, 0, 255) then return false, 'bad prop texture' end
        end
    end
    return true
end

-- ------------------------------------------------------------- transforms

function S.ValidateTransform(t)
    if type(t) ~= 'table' then return false, 'transform not a table' end
    for _, k in ipairs({ 'x', 'y', 'z', 'heading' }) do
        local v = t[k]
        if type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge then
            return false, 'bad transform field ' .. k
        end
    end
    if math.abs(t.x) > 20000 or math.abs(t.y) > 20000 or t.z < -300 or t.z > 3000 then
        return false, 'transform out of world bounds'
    end
    return true
end

-- ---------------------------------------------------------- display input

local VALID_TYPES = {}
for _, v in pairs(KTR.Const.DisplayType) do VALID_TYPES[v] = true end
local VALID_SCOPES = {}
for _, v in pairs(KTR.Const.ScopeType) do VALID_SCOPES[v] = true end

function S.ValidateDisplayInput(d, cfg)
    cfg = cfg or KTR.Config
    if type(d) ~= 'table' then return false, 'display not a table' end
    if not VALID_TYPES[d.displayType] then return false, 'bad display type' end
    if not VALID_SCOPES[d.scopeType] then return false, 'bad scope type' end
    if d.scopeType ~= C.ScopeType.WORLD and not isStr(d.scopeId, 64) then
        return false, 'scopeId required for shell/property scope'
    end
    local ok, err = S.ValidateTransform(d.transform)
    if not ok then return false, err end
    if d.label ~= nil and not isStr(d.label, cfg.Limits.LabelLength) then
        return false, 'label too long'
    end
    if d.description ~= nil and not isStr(d.description, cfg.Limits.DescriptionLength) then
        return false, 'description too long'
    end
    if d.poseId ~= nil and not isStr(d.poseId, 32) then return false, 'bad pose id' end
    if d.platform ~= nil and not isStr(d.platform, 32) then return false, 'bad platform' end
    if d.caseStyle ~= nil and not isStr(d.caseStyle, 16) then return false, 'bad case style' end
    if d.settings ~= nil then
        local ok, err = S.ValidateSettings(d.settings, cfg)
        if not ok then return false, err end
    end

    if d.displayType == C.DisplayType.MANNEQUIN then
        if d.gender ~= C.Gender.MALE and d.gender ~= C.Gender.FEMALE then
            return false, 'mannequin requires gender'
        end
        if d.outfit ~= nil then
            local okO, errO = S.ValidateOutfit(d.outfit)
            if not okO then return false, 'outfit: ' .. tostring(errO) end
        end
    elseif d.displayType:find('^weapon_') then
        if type(d.item) ~= 'table' then return false, 'weapon display requires item' end
        if not isStr(d.item.name, 64) then return false, 'bad item name' end
        if d.item.metadata ~= nil and type(d.item.metadata) ~= 'table' then
            return false, 'bad item metadata'
        end
    end
    return true
end

---Per-display settings: currently { rotate = { enabled, speed } }.
function S.ValidateSettings(s, cfg)
    cfg = cfg or KTR.Config
    if type(s) ~= 'table' then return false, 'settings not a table' end
    for k in pairs(s) do
        if k ~= 'rotate' then return false, 'unknown settings key ' .. tostring(k) end
    end
    if s.rotate ~= nil then
        local r = s.rotate
        if type(r) ~= 'table' then return false, 'rotate not a table' end
        if type(r.enabled) ~= 'boolean' then return false, 'rotate.enabled must be boolean' end
        local sp = r.speed
        if sp ~= nil then
            if type(sp) ~= 'number' or sp ~= sp
                or sp < cfg.Display.MinRotateSpeed or sp > cfg.Display.MaxRotateSpeed then
                return false, 'rotate.speed out of range'
            end
        end
    end
    return true
end

-- serialized payload size guard (server side, before json decode cost matters
-- use on the encoded string)
function S.CheckPayloadSize(encoded, cfg)
    cfg = cfg or KTR.Config
    return type(encoded) == 'string' and #encoded <= cfg.Limits.OutfitPayloadBytes
end
