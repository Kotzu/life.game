-- Client-side half of the request/response callback system.
--   LifeCore.TriggerCallback('lifecore:getOnlineCount', function(count)
--       print(count)
--   end)

local pending = {}
local nextRequestId = 0

---@param name string callback registered on the server
---@param cb fun(...) receives whatever the server handler passed to its cb
---@param ... any extra arguments forwarded to the server handler
function LifeCore.TriggerCallback(name, cb, ...)
    nextRequestId = nextRequestId + 1
    local requestId = nextRequestId
    pending[requestId] = cb
    TriggerServerEvent('lifecore:cb:trigger', name, requestId, ...)
end

--- Promise-style variant usable inside a CreateThread coroutine:
---   local count = LifeCore.AwaitCallback('lifecore:getOnlineCount')
---@param name string
---@param ... any
---@return any
function LifeCore.AwaitCallback(name, ...)
    local p = promise.new()
    LifeCore.TriggerCallback(name, function(...)
        p:resolve({ ... })
    end, ...)
    return table.unpack(Citizen.Await(p))
end

RegisterNetEvent('lifecore:cb:response', function(requestId, ...)
    local cb = pending[requestId]
    if not cb then return end
    pending[requestId] = nil
    cb(...)
end)
