--[[ Client access to mannequin_manifest.json (streamed by kotzu_mannequin_assets). ]]

KTRC = KTRC or {}
KTRC.Manifest = {}
local M = KTRC.Manifest
local C = KTR.Const

local data = nil

function M.Load(force)
    if data and not force then return data end
    local text = LoadResourceFile(C.ASSETS_RESOURCE, 'mannequin_manifest.json')
    if not text then
        print('[kotzu_trophy] mannequin_manifest.json not readable — is kotzu_mannequin_assets started?')
        return nil
    end
    local ok, decoded = pcall(json.decode, text)
    data = ok and decoded or nil
    if data then
        print(('[kotzu_trophy] manifest v%s loaded (collection "%s")')
            :format(tostring(data.version), tostring(data.collection)))
    end
    return data
end

function M.Version()
    local m = M.Load()
    return m and m.version or 0
end

function M.Built()
    return M.Version() >= 1
end

---Garment verdict: status string + converted mapping if any.
---@return string status, table|nil converted
function M.GarmentStatus(gender, compId, collection, drawable)
    local m = M.Load()
    if not m then return C.GarmentStatus.PENDING, nil end
    local g = m.genders[gender]
    if not g then return C.GarmentStatus.PENDING, nil end
    local key = ('%s:comp%d:%s:%d'):format(gender, compId, collection or '', drawable)
    local entry = g.garments[key]
    if not entry then return 'unknown', nil end
    return entry.status, entry.converted
end

---Mannequin body variant for a base-skin component.
---@return number|nil localIndex in the mannequin collection
function M.BodyDrawable(gender, compId, sourceCollection, sourceDrawable)
    local m = M.Load()
    if not m then return nil end
    local g = m.genders[gender]
    local body = g and g.body[tostring(compId)]
    if not body or not body.variants then return nil end
    local src = ('%s:%d'):format(sourceCollection or '', sourceDrawable or 0)
    return body.variants[src] or body.variants[':0'] or next(body.variants) and body.variants[next(body.variants)]
end

RegisterNetEvent('kotzu_trophy:client:reloadManifest', function()
    M.Load(true)
end)
