--[[
    Permission policy (brief §12/§13). Ownership, co-ownership (via housing
    resolver), job+grade grants stored on the display, admin ace, visitor.
]]

KTRS = KTRS or {}
KTRS.Perms = {}
local P = KTRS.Perms
local C = KTR.Const

local function framework()
    return KTR.Bridge.Get('framework')
end

local function housing()
    return KTR.Bridge.Get('housing')
end

function P.Identity(src)
    local fw = framework()
    return fw and fw.GetIdentity(src) or nil
end

function P.IsAdmin(src)
    local fw = framework()
    return fw and fw.IsAdmin(src) or false
end

---Full capability decision for one display.
---@return table caps { view, inspect, manage, remove, tryOn, equip }
function P.Capabilities(src, display)
    local id = P.Identity(src)
    if not id then return { view = false } end
    local caps = { view = true, inspect = true, manage = false, remove = false,
                   tryOn = false, equip = false }

    if P.IsAdmin(src) then
        caps.manage, caps.remove, caps.tryOn, caps.equip = true, true, true, true
        return caps
    end
    if display.owner == id.citizenid then
        caps.manage, caps.remove = true, true
        caps.tryOn, caps.equip = true, true
        return caps
    end

    -- co-owner via housing resolver for shell/property scopes
    if display.scopeType ~= C.ScopeType.WORLD then
        local h = housing()
        local res = h and h.ResolveScope(src, display.scopeType, display.scopeId)
        if res and res.allowed and (res.owner or res.coOwner) then
            caps.manage, caps.remove = true, true
        end
    end

    -- job/grade grants stored on the display record
    local perms = display.permissions or {}
    if perms.job and id.job == perms.job then
        local needGrade = tonumber(perms.grade) or 0
        if (id.grade or 0) >= needGrade then
            if perms.jobCanManage then caps.manage = true end
            if perms.jobCanRemove then caps.remove = true end
        end
    end

    -- visitor allowances from config + per-display flags
    if KTR.Config.Interaction.AllowVisitorTryOn and perms.visitorTryOn ~= false then
        caps.tryOn = true
    end
    if KTR.Config.Interaction.AllowVisitorEquip and perms.visitorEquip == true then
        caps.equip = true
    end
    return caps
end

---Placement authorization for a scope (before a display exists).
---@return boolean ok, table|string resOrErr
function P.CanPlaceInScope(src, scopeType, scopeId)
    local h = housing()
    local res = h and h.ResolveScope(src, scopeType, scopeId) or { allowed = false }
    if not res.allowed then return false, C.Err.NOT_ALLOWED end
    if scopeType ~= C.ScopeType.WORLD and not (res.owner or res.coOwner or P.IsAdmin(src)) then
        return false, C.Err.NOT_ALLOWED
    end
    return true, res
end
