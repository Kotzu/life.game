--[[
    Housing/shell bridge (shared, side-gated) — brief §16.

    The trophy room never depends on one housing product. Housing scripts (or
    the test harness) integrate through this contract:

    CLIENT exports (call from your housing resource):
        exports.kotzu_trophy_room:EnterRoom({
            scopeType = 'shell'|'property', scopeId = 'prop_1234',
            origin = vector4(x, y, z, heading),  -- shell/property origin
            permissions = { owner = true, coOwner = false, job = nil },
        })
        exports.kotzu_trophy_room:ExitRoom()

    SERVER exports:
        exports.kotzu_trophy_room:RegisterScopeResolver(fn)
            -- fn(src, scopeType, scopeId) -> { allowed=bool, owner=bool,
            --    coOwner=bool, bucket=int|nil, origin=vector4|nil }
            -- lets the housing product answer authorization questions

    EVENTS emitted by this bridge:
        client: 'kotzu_trophy:room:entered' (roomState), 'kotzu_trophy:room:exited'
]]

local isServer = IsDuplicityVersion()

local impl = {
    detect = function() return true end,
}

if not isServer then
    local current = nil -- { scopeType, scopeId, origin, permissions }

    function impl.EnterRoom(data)
        if type(data) ~= 'table' or type(data.scopeId) ~= 'string' then return false end
        current = {
            scopeType = data.scopeType or KTR.Const.ScopeType.SHELL,
            scopeId = data.scopeId,
            origin = data.origin,
            permissions = data.permissions or {},
        }
        TriggerEvent('kotzu_trophy:room:entered', current)
        return true
    end

    function impl.ExitRoom()
        current = nil
        TriggerEvent('kotzu_trophy:room:exited')
    end

    function impl.CurrentRoom()
        return current
    end

    ---World transform for a display record, resolving shell-relative storage.
    function impl.ToWorld(display)
        local t = display.transform
        if display.scopeType == KTR.Const.ScopeType.WORLD or not current or not current.origin then
            return t
        end
        local o = current.origin
        return {
            x = o.x + t.x, y = o.y + t.y, z = o.z + t.z,
            heading = (o.w + t.heading) % 360.0,
        }
    end

    ---Local transform for storage, given a world position inside the room.
    function impl.ToLocal(world)
        if not current or not current.origin then return world end
        local o = current.origin
        return {
            x = world.x - o.x, y = world.y - o.y, z = world.z - o.z,
            heading = (world.heading - o.w) % 360.0,
        }
    end

    exports('EnterRoom', impl.EnterRoom)
    exports('ExitRoom', impl.ExitRoom)
    exports('CurrentRoom', impl.CurrentRoom)
else
    local resolver = nil

    function impl.RegisterScopeResolver(fn)
        if type(fn) == 'function' then resolver = fn return true end
        return false
    end

    ---Server-side authorization for a scope. Falls back to test shells and,
    ---for world scope, distance validation done by the caller.
    function impl.ResolveScope(src, scopeType, scopeId)
        if scopeType == KTR.Const.ScopeType.WORLD then
            return { allowed = true, owner = false, bucket = GetPlayerRoutingBucket(src) }
        end
        if resolver then
            local ok, res = pcall(resolver, src, scopeType, scopeId)
            if ok and type(res) == 'table' then return res end
            return { allowed = false }
        end
        -- test shells (acceptance harness): scopeId must match a configured shell
        for _, shell in ipairs(KTR.Config.Housing.TestShells) do
            if shell.shellId == scopeId then
                return {
                    allowed = true, owner = true,
                    bucket = shell.bucket, origin = shell.origin,
                }
            end
        end
        return { allowed = false }
    end

    exports('RegisterScopeResolver', impl.RegisterScopeResolver)
end

KTR.Bridge.Register('housing', 'generic', 0, impl)
