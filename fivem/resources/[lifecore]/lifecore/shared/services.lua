-- Service registry: swappable modules behind stable contracts.
--
-- The problem this solves: on classic frameworks, resources talk directly to
-- whichever inventory/phone/target resource happens to be installed, so
-- swapping one breaks everything that touched it. Here, resources only ever
-- talk to a named service through the core:
--
--     local inv = exports['lifecore']:GetService('inventory')
--     inv.AddItem(source, 'water', 1)
--
-- and any resource can *be* that service by registering an implementation
-- that fulfils the contract:
--
--     exports['lifecore']:RegisterService('inventory', {
--         AddItem = function(source, item, count) ... end,
--         RemoveItem = function(source, item, count) ... end,
--         GetItemCount = function(source, item) ... end,
--     })
--
-- Swap the providing resource and nothing else on the server changes.
-- Registrations are automatically dropped when the providing resource stops,
-- so a dead provider can never be called.

LifeServices = {
    providers = {}, -- name -> implementation table
    owners = {},    -- name -> resource that registered it
}

-- Required methods per service name. A registration that misses a method is
-- rejected loudly at register time instead of exploding at call time later.
-- Contracts are intentionally minimal: they describe what *consumers* rely
-- on; implementations are free to offer more.
LifeServices.Contracts = {
    -- server-side
    inventory = { 'AddItem', 'RemoveItem', 'GetItemCount' },
    -- client-side
    notify = { 'Send' },              -- Send(message, level)
    progress = { 'Start' },           -- Start(label, durationMs, cb)
    target = { 'AddEntity', 'RemoveEntity' },
    phone = { 'Open', 'Close', 'IsOpen' },
    fuel = { 'GetFuel', 'SetFuel' },
}

---@param name string service name (see LifeServices.Contracts)
---@param impl table implementation fulfilling the contract
---@param owner string resource registering the implementation
function LifeServices.Register(name, impl, owner)
    local contract = LifeServices.Contracts[name]
    if contract then
        for _, method in ipairs(contract) do
            if type(impl[method]) ~= 'function' then
                error(("service '%s' from '%s' is missing required method '%s'")
                    :format(name, owner, method))
            end
        end
    end
    local previous = LifeServices.owners[name]
    LifeServices.providers[name] = impl
    LifeServices.owners[name] = owner
    if previous and previous ~= owner then
        print(("[lifecore] service '%s' now provided by '%s' (was '%s')")
            :format(name, owner, previous))
    else
        LifeUtils.Debug('service registered', name, 'by', owner)
    end
    TriggerEvent('lifecore:serviceChanged', name, owner)
end

--- Current implementation of a service, or nil if none registered.
---@param name string
---@return table|nil
function LifeServices.Get(name)
    return LifeServices.providers[name]
end

--- Block (in a thread) until a service is available.
---@param name string
---@param timeoutMs number|nil default 10000
---@return table|nil nil on timeout
function LifeServices.Await(name, timeoutMs)
    local deadline = GetGameTimer() + (timeoutMs or 10000)
    while not LifeServices.providers[name] do
        if GetGameTimer() > deadline then return nil end
        Wait(50)
    end
    return LifeServices.providers[name]
end

-- Drop every service owned by a resource that stops: consumers get a clean
-- nil from GetService instead of calling into a dead function reference.
AddEventHandler('onResourceStop', function(resource)
    for name, owner in pairs(LifeServices.owners) do
        if owner == resource then
            LifeServices.providers[name] = nil
            LifeServices.owners[name] = nil
            print(("[lifecore] service '%s' unregistered (resource '%s' stopped)")
                :format(name, resource))
            TriggerEvent('lifecore:serviceChanged', name, nil)
        end
    end
end)
