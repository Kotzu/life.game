--[[
    Bridge registry. Implementations self-register with a detect() function and
    a priority; the first detected impl (highest priority) wins. Every consumer
    goes through KTR.Bridge.Get(kind) so swapping products never touches core code.
]]

KTR = KTR or {}
KTR.Bridge = { _impls = {}, _resolved = {} }
local B = KTR.Bridge

function B.Register(kind, name, priority, impl)
    B._impls[kind] = B._impls[kind] or {}
    impl.__name = name
    impl.__priority = priority or 0
    table.insert(B._impls[kind], impl)
end

function B.Get(kind)
    local cached = B._resolved[kind]
    if cached then return cached end
    local impls = B._impls[kind] or {}
    table.sort(impls, function(a, b) return a.__priority > b.__priority end)
    for _, impl in ipairs(impls) do
        local ok, detected = pcall(impl.detect)
        if ok and detected then
            B._resolved[kind] = impl
            print(('[kotzu_trophy] bridge %s -> %s'):format(kind, impl.__name))
            if impl.init then pcall(impl.init) end
            return impl
        end
    end
    print(('[kotzu_trophy] WARNING: no bridge detected for %s'):format(kind))
    return nil
end

--[[
    Export probing done RIGHT.

    In FiveM, INDEXING a missing export does not raise — `exports.res.name`
    always returns a callable; the error ("No such export … in resource …")
    only happens when you CALL it. So a probe that merely indexes reports every
    candidate as present and then fails at use time. These helpers call the
    export and classify the failure instead.
]]

---@return boolean ok, any resultOrError, boolean missing
function B.TryExport(resource, exportName, ...)
    local args = table.pack(...)
    local ok, res = pcall(function()
        return exports[resource][exportName](nil, table.unpack(args, 1, args.n))
    end)
    if ok then return true, res, false end
    local msg = tostring(res)
    local missing = msg:find('No such export') ~= nil
        or msg:find('attempt to call a nil value') ~= nil
    return false, res, missing
end

---Resolve the first candidate export that actually exists, caching the winner.
---`probeArgs` are passed to the call used for probing (use read-only getters).
---@return string|nil exportName
function B.ResolveExport(cache, key, resource, candidates, probeArgs)
    if cache[key] ~= nil then
        return cache[key] or nil
    end
    for _, name in ipairs(candidates) do
        local ok, _, missing = B.TryExport(resource, name,
            table.unpack(probeArgs or {}))
        if ok or not missing then
            -- exists (it either returned, or failed for its own reasons)
            cache[key] = name
            return name
        end
    end
    cache[key] = false
    return nil
end

---Find a specific registered impl by name (regardless of detection winner).
function B.Find(kind, name)
    for _, impl in ipairs(B._impls[kind] or {}) do
        if impl.__name == name then return impl end
    end
    return nil
end

function B.Describe()
    local out = {}
    for kind, impls in pairs(B._impls) do
        local names = {}
        for _, i in ipairs(impls) do names[#names + 1] = i.__name end
        local active = B._resolved[kind]
        out[kind] = { available = names, active = active and active.__name or nil }
    end
    return out
end

function KTR.Started(res)
    return GetResourceState(res) == 'started' or GetResourceState(res) == 'starting'
end
