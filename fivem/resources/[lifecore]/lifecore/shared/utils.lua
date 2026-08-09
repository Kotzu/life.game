LifeUtils = {}

--- Round a number to the given number of decimal places.
---@param value number
---@param decimals number|nil
---@return number
function LifeUtils.Round(value, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(value * mult + 0.5) / mult
end

--- Clamp a number between min and max.
---@param value number
---@param min number
---@param max number
---@return number
function LifeUtils.Clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

--- Shallow-copy a table.
---@param tbl table
---@return table
function LifeUtils.ShallowCopy(tbl)
    local copy = {}
    for k, v in pairs(tbl) do
        copy[k] = v
    end
    return copy
end

--- Deep-copy a table (handles nested tables, not cycles).
---@param tbl table
---@return table
function LifeUtils.DeepCopy(tbl)
    if type(tbl) ~= 'table' then return tbl end
    local copy = {}
    for k, v in pairs(tbl) do
        copy[k] = type(v) == 'table' and LifeUtils.DeepCopy(v) or v
    end
    return copy
end

--- Debug print, gated behind Config.Debug.
function LifeUtils.Debug(...)
    if not Config.Debug then return end
    local args = { ... }
    for i = 1, #args do
        if type(args[i]) == 'table' then
            args[i] = json.encode(args[i])
        else
            args[i] = tostring(args[i])
        end
    end
    print(('[lifecore:debug] %s'):format(table.concat(args, ' ')))
end

--- Format a money amount for display, e.g. 12500 -> "$12,500".
---@param amount number
---@return string
function LifeUtils.FormatMoney(amount)
    local formatted = tostring(math.floor(amount))
    while true do
        local replaced
        formatted, replaced = formatted:gsub('^(-?%d+)(%d%d%d)', '%1,%2')
        if replaced == 0 then break end
    end
    return '$' .. formatted
end
