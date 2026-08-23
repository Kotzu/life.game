--[[
    Auto-rotate controller for displayed items (brief follow-up: showcase spin).

    Perf contract: the per-frame loop exists ONLY while at least one rotating
    entity is registered (i.e. a rotating display is streamed in); it exits
    completely when the registry empties. Registration happens from the
    renderers on spawn and is cleaned on despawn.
]]

KTRC = KTRC or {}
KTRC.Rotator = {}
local R = KTRC.Rotator

local items = {}   -- entity -> degrees/second
local count = 0
local running = false

local function loop()
    running = true
    local last = GetGameTimer()
    while count > 0 do
        Wait(0)
        local now = GetGameTimer()
        local dt = (now - last) / 1000.0
        last = now
        for entity, speed in pairs(items) do
            if DoesEntityExist(entity) then
                SetEntityHeading(entity, (GetEntityHeading(entity) + speed * dt) % 360.0)
            else
                items[entity] = nil
                count = count - 1
            end
        end
    end
    running = false
end

---@param entity number
---@param speed number degrees/second (clamped to config bounds)
function R.Add(entity, speed)
    local cfg = KTR.Config.Display
    speed = math.max(cfg.MinRotateSpeed, math.min(cfg.MaxRotateSpeed,
        tonumber(speed) or cfg.DefaultRotateSpeed))
    if items[entity] == nil then count = count + 1 end
    items[entity] = speed
    if not running then CreateThread(loop) end
end

function R.Remove(entity)
    if items[entity] ~= nil then
        items[entity] = nil
        count = count - 1
    end
end

function R.Active()
    return count
end
