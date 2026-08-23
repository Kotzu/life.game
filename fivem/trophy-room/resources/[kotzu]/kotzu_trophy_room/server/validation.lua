--[[
    Server-side validation (brief §18): every client payload is untrusted.
    Layers: schema validation (shared), payload size, distance, bucket match,
    pose/platform whitelists, and mannequin-manifest outfit compatibility
    (defense in depth — the client refuses too, but the server is authoritative).
]]

KTRS = KTRS or {}
KTRS.Validate = {}
local V = KTRS.Validate
local C = KTR.Const

local manifest = nil

function V.Manifest()
    if manifest then return manifest end
    local text = LoadResourceFile(C.ASSETS_RESOURCE, 'mannequin_manifest.json')
    if not text then return nil end
    local ok, decoded = pcall(json.decode, text)
    manifest = ok and decoded or nil
    return manifest
end

function V.ReloadManifest()
    manifest = nil
    return V.Manifest()
end

local poseSet, platformSet
local function whitelists()
    if not poseSet then
        poseSet, platformSet = {}, {}
        for _, p in ipairs(KTR.Config.Poses) do poseSet[p.id] = true end
        for _, p in ipairs(KTR.Config.Platforms) do platformSet[p.id] = true end
    end
    return poseSet, platformSet
end

---Manifest verdict for one outfit: supported / incompatible / manifest missing.
---@return boolean ok, string|nil errCode, table detail
function V.CheckOutfitCompatibility(outfit)
    local m = V.Manifest()
    if not m or (m.version or 0) < 1 then
        return false, C.Err.MANIFEST_NOT_BUILT, {}
    end
    local g = m.genders[outfit.gender]
    if not g then return false, C.Err.MANIFEST_NOT_BUILT, {} end

    local blockers = {}
    for compId, comp in pairs(outfit.components) do
        local idNum = tonumber(compId)
        local isBody = false
        for _, b in ipairs(C.BodyComponents) do
            if b == idNum then isBody = true break end
        end
        if not isBody and idNum ~= C.Comp.TEEF then
            local key = ('%s:comp%d:%s:%d'):format(outfit.gender, idNum, comp.collection, comp.drawable)
            local entry = g.garments[key]
            local status = entry and entry.status or nil
            if status == C.GarmentStatus.SKIN_FREE or status == C.GarmentStatus.CONVERTED then
                -- ok
            elseif status == nil then
                -- unknown garment (not in catalog — e.g. new addon pack not yet scanned)
                blockers[#blockers + 1] = { key = key, status = 'unknown' }
            else
                blockers[#blockers + 1] = { key = key, status = status }
            end
        end
    end
    if #blockers > 0 then
        return false, C.Err.OUTFIT_INCOMPATIBLE, { blockers = blockers }
    end
    return true, nil, {}
end

---Validate a display placement/update payload end to end.
---@return boolean ok, string|nil errCode, string|nil detail
function V.DisplayInput(src, d)
    if type(d) ~= 'table' then return false, C.Err.BAD_INPUT, 'not a table' end
    local encoded = json.encode(d)
    if not KTR.Schemas.CheckPayloadSize(encoded) then
        return false, C.Err.BAD_INPUT, 'payload too large'
    end
    local ok, err = KTR.Schemas.ValidateDisplayInput(d)
    if not ok then return false, C.Err.BAD_INPUT, err end

    local poses, platforms = whitelists()
    if d.poseId and not poses[d.poseId] then return false, C.Err.BAD_INPUT, 'unknown pose' end
    if d.platform and not platforms[d.platform] then return false, C.Err.BAD_INPUT, 'unknown platform' end
    if d.caseStyle and not KTR.Config.Weapons.CaseStyles[d.caseStyle] then
        return false, C.Err.BAD_INPUT, 'unknown case style'
    end

    -- distance check: the resolved WORLD position must be near the player
    local ped = GetPlayerPed(src)
    if ped and ped > 0 then
        local ppos = GetEntityCoords(ped)
        local world = d.worldTransform or d.transform
        if d.scopeType ~= C.ScopeType.WORLD and d.worldTransform == nil then
            -- shell-relative without world hint: rely on scope resolver origin
            local h = KTR.Bridge.Get('housing')
            local res = h and h.ResolveScope(src, d.scopeType, d.scopeId)
            if res and res.origin then
                world = { x = res.origin.x + d.transform.x, y = res.origin.y + d.transform.y,
                          z = res.origin.z + d.transform.z }
            end
        end
        if world then
            local dist = #(ppos - vector3(world.x, world.y, world.z))
            if dist > KTR.Config.Placement.MaxDistance + 5.0 then
                return false, C.Err.BAD_INPUT, ('placement %.1fm from player'):format(dist)
            end
        end
    end

    -- bucket integrity: display is stored with the SERVER-observed bucket
    d.bucket = GetPlayerRoutingBucket(src)

    if d.displayType == C.DisplayType.MANNEQUIN and d.outfit then
        local okC, errC, detail = V.CheckOutfitCompatibility(d.outfit)
        if not okC then return false, errC, json.encode(detail) end
        local m = V.Manifest()
        d.manifestVersion = m and m.version or 0
    end
    return true
end
