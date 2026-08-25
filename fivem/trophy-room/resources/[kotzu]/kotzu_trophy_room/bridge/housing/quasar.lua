--[[
    Housing bridge: qs-housing (Quasar). Shared file, side-gated.

    qs-housing is closed-source, so this bridge does not assume an API. It
    works on three levels, strongest first:

    1. **Events** — if qs-housing emits enter/exit events under any of the
       candidate names below, we pick them up automatically.
    2. **Exports** — property lookup is resolved at runtime from candidates
       (Bridge.ResolveExport actually CALLS them, so a missing export is
       detected rather than assumed present).
    3. **Manual hook (always works)** — two lines in your housing script:

         -- when the player enters a property interior:
         exports.kotzu_trophy_room:EnterRoom({
             scopeType = 'property',
             scopeId   = tostring(propertyId),
             origin    = vector4(shellX, shellY, shellZ, shellHeading),
             permissions = { owner = isOwner, coOwner = hasKeys },
         })
         -- when they leave:
         exports.kotzu_trophy_room:ExitRoom()

    Server side, register a resolver so ownership is authoritative:

         exports.kotzu_trophy_room:RegisterScopeResolver(function(src, scopeType, scopeId)
             local prop = <your lookup>(scopeId)
             return {
                 allowed = prop ~= nil,
                 owner   = prop and prop.owner == GetCitizenId(src),
                 coOwner = prop and HasKeys(src, scopeId),
                 bucket  = <routing bucket for that instance>,
                 origin  = vector4(prop.x, prop.y, prop.z, prop.h),
             }
         end)

    Level 3 is the supported path; 1 and 2 are conveniences that light up
    automatically when the installed build exposes them. `/kmq:bridges` shows
    which level is active.
]]

local isServer = IsDuplicityVersion()
local RES = 'qs-housing'
local resolved = {}

local ENTER_EVENTS = {
    'qs-housing:client:enteredProperty', 'qs-housing:client:enterProperty',
    'qs-housing:enteredHouse', 'qs-housing:client:insideHouse',
}
local EXIT_EVENTS = {
    'qs-housing:client:leftProperty', 'qs-housing:client:exitProperty',
    'qs-housing:leftHouse', 'qs-housing:client:outsideHouse',
}
local PROPERTY_EXPORTS = {
    getProperty = { 'GetProperty', 'getProperty', 'GetHouse', 'getHouse' },
    isOwner     = { 'IsPropertyOwner', 'isPropertyOwner', 'IsHouseOwner' },
}

local impl = {
    detect = function() return KTR.Started(RES) end,
}

local function generic()
    return KTR.Bridge.Find('housing', 'generic')
end

if not isServer then
    -- Auto-wire to whichever enter/exit events this build emits. The payload
    -- shape varies, so we accept the common spellings and fall back to the
    -- manual hook when nothing usable arrives.
    local function normalize(data)
        if type(data) ~= 'table' then return nil end
        local id = data.propertyId or data.property_id or data.house
            or data.houseId or data.id or data.property
        if id == nil then return nil end
        local c = data.coords or data.shellCoords or data.entrance
        local origin
        if type(c) == 'table' or type(c) == 'vector4' or type(c) == 'vector3' then
            origin = vector4(c.x or c[1] or 0.0, c.y or c[2] or 0.0,
                             c.z or c[3] or 0.0, c.w or c.h or data.heading or 0.0)
        end
        return {
            scopeType = KTR.Const.ScopeType.PROPERTY,
            scopeId = tostring(id),
            origin = origin,
            permissions = {
                owner = data.owner == true or data.isOwner == true,
                coOwner = data.hasKeys == true or data.keyholder == true,
            },
        }
    end

    for _, evName in ipairs(ENTER_EVENTS) do
        AddEventHandler(evName, function(data)
            local room = normalize(data)
            if room then
                local g = generic()
                if g then g.EnterRoom(room) end
                if KTR.Config.Debug then
                    print(('[kotzu_trophy] qs-housing enter via %s -> %s')
                        :format(evName, room.scopeId))
                end
            elseif KTR.Config.Debug then
                print(('[kotzu_trophy] qs-housing %s fired but the payload had no '
                    .. 'property id — use the manual EnterRoom hook'):format(evName))
            end
        end)
    end
    for _, evName in ipairs(EXIT_EVENTS) do
        AddEventHandler(evName, function()
            local g = generic()
            if g then g.ExitRoom() end
        end)
    end

    -- delegate the transform helpers to the generic bridge
    function impl.EnterRoom(data) return generic().EnterRoom(data) end
    function impl.ExitRoom() return generic().ExitRoom() end
    function impl.CurrentRoom() return generic().CurrentRoom() end
    function impl.ToWorld(d) return generic().ToWorld(d) end
    function impl.ToLocal(w) return generic().ToLocal(w) end
else
    ---Try qs-housing's own property lookup; fall back to the generic resolver
    ---(test shells / a registered custom resolver) when unavailable.
    function impl.ResolveScope(src, scopeType, scopeId)
        if scopeType == KTR.Const.ScopeType.WORLD then
            return { allowed = true, owner = false, bucket = GetPlayerRoutingBucket(src) }
        end

        local getProp = KTR.Bridge.ResolveExport(resolved, 'getProperty', RES,
            PROPERTY_EXPORTS.getProperty, { scopeId })
        if getProp then
            local ok, prop = KTR.Bridge.TryExport(RES, getProp, scopeId)
            if ok and type(prop) == 'table' then
                local id = KTRS.Perms.Identity(src)
                local citizenid = id and id.citizenid
                local owner = prop.owner or prop.citizenid or prop.owner_citizenid
                local isOwner = citizenid ~= nil and owner == citizenid
                local coOwner = false
                local isOwnerExport = KTR.Bridge.ResolveExport(resolved, 'isOwner', RES,
                    PROPERTY_EXPORTS.isOwner, { src, scopeId })
                if isOwnerExport and not isOwner then
                    local okO, res = KTR.Bridge.TryExport(RES, isOwnerExport, src, scopeId)
                    coOwner = okO and res == true
                end
                local c = prop.coords or prop.entrance or prop.shellCoords
                return {
                    allowed = true,
                    owner = isOwner,
                    coOwner = coOwner,
                    bucket = tonumber(prop.bucket or prop.instance)
                        or GetPlayerRoutingBucket(src),
                    origin = c and vector4(c.x or 0.0, c.y or 0.0, c.z or 0.0,
                                           c.w or c.h or 0.0) or nil,
                }
            end
        end
        -- no usable export: defer to the generic bridge (custom resolver or
        -- test shells). Never silently allow.
        local g = generic()
        return g and g.ResolveScope(src, scopeType, scopeId) or { allowed = false }
    end

    function impl.RegisterScopeResolver(fn)
        return generic().RegisterScopeResolver(fn)
    end
end

function impl.Describe()
    return { resource = RES, resolvedExports = resolved,
             enterEvents = ENTER_EVENTS, note = 'manual EnterRoom hook always works' }
end

KTR.Bridge.Register('housing', 'qs-housing', 20, impl)
