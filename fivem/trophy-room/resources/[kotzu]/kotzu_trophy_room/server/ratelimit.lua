--[[ Sliding-window rate limiter, per player + action (brief §18). ]]

KTRS = KTRS or {}
KTRS.RateLimit = {}
local RL = KTRS.RateLimit

local windows = {} -- src -> action -> { timestamps }

---@return boolean allowed
function RL.Check(src, action)
    local limit = KTR.Config.RateLimit[action]
    if not limit then return true end
    local now = os.clock() * 1000
    windows[src] = windows[src] or {}
    local w = windows[src][action] or {}
    local fresh = {}
    for _, t in ipairs(w) do
        if now - t < 60000 then fresh[#fresh + 1] = t end
    end
    if #fresh >= limit then
        windows[src][action] = fresh
        return false
    end
    fresh[#fresh + 1] = now
    windows[src][action] = fresh
    return true
end

AddEventHandler('playerDropped', function()
    windows[source] = nil
end)
