--[[
    Minimal promise-style RPC over events (framework-agnostic, no polling).

    Client:  local res = KTR.RPC.Call('displays:list', { ... })
    Server:  KTR.RPC.Register('displays:list', function(src, args) return {...} end)
]]

KTR = KTR or {}
KTR.RPC = {}
local RPC = KTR.RPC

local PREFIX = 'kotzu_trophy:rpc:'
local isServer = IsDuplicityVersion()

if isServer then
    local handlers = {}

    function RPC.Register(name, fn)
        handlers[name] = fn
    end

    RegisterNetEvent(PREFIX .. 'request', function(name, reqId, args)
        local src = source
        local fn = handlers[name]
        if type(reqId) ~= 'string' or #reqId > 64 then return end
        if not fn then
            TriggerClientEvent(PREFIX .. 'response', src, reqId, false, 'no such rpc')
            return
        end
        local ok, resultOrErr, err = pcall(fn, src, args)
        if ok then
            -- handler returns (result) or (nil, errCode)
            if resultOrErr == nil and err ~= nil then
                TriggerClientEvent(PREFIX .. 'response', src, reqId, false, err)
            else
                TriggerClientEvent(PREFIX .. 'response', src, reqId, true, resultOrErr)
            end
        else
            print(('[kotzu_trophy] rpc %s error: %s'):format(name, tostring(resultOrErr)))
            TriggerClientEvent(PREFIX .. 'response', src, reqId, false, KTR.Const.Err.INTERNAL)
        end
    end)
else
    local pending = {}
    local counter = 0

    RegisterNetEvent(PREFIX .. 'response', function(reqId, ok, payload)
        local p = pending[reqId]
        if not p then return end
        pending[reqId] = nil
        p.ok, p.payload, p.done = ok, payload, true
    end)

    ---Blocking call from a coroutine/thread. Returns (result) or (nil, err).
    function RPC.Call(name, args, timeoutMs)
        counter = counter + 1
        local reqId = ('%d_%d'):format(GetGameTimer(), counter)
        local p = { done = false }
        pending[reqId] = p
        TriggerServerEvent(PREFIX .. 'request', name, reqId, args)
        local deadline = GetGameTimer() + (timeoutMs or 10000)
        while not p.done do
            if GetGameTimer() > deadline then
                pending[reqId] = nil
                return nil, 'timeout'
            end
            Wait(25)
        end
        if p.ok then return p.payload end
        return nil, p.payload
    end
end
