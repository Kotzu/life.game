-- Minimal pure-Lua JSON (encode/decode) for the FXServer simulator.
-- Not a general-purpose library; sufficient for the resource's payloads.

local json = {}

local escapes = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
                  ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

local function isArray(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= 'number' then return false end
        n = n + 1
    end
    for i = 1, n do
        if t[i] == nil then return false end
    end
    return true, n
end

function json.encode(v)
    local tv = type(v)
    if v == nil then return 'null'
    elseif tv == 'boolean' then return v and 'true' or 'false'
    elseif tv == 'number' then
        if v ~= v or v == math.huge or v == -math.huge then return 'null' end
        if v == math.floor(v) and math.abs(v) < 2^53 then return ('%d'):format(v) end
        return ('%.14g'):format(v)
    elseif tv == 'string' then
        return '"' .. v:gsub('[%c"\\]', function(c)
            return escapes[c] or ('\\u%04x'):format(c:byte())
        end) .. '"'
    elseif tv == 'table' then
        local arr, n = isArray(v)
        local out = {}
        if arr then
            for i = 1, n do out[i] = json.encode(v[i]) end
            return '[' .. table.concat(out, ',') .. ']'
        end
        for k, val in pairs(v) do
            out[#out + 1] = json.encode(tostring(k)) .. ':' .. json.encode(val)
        end
        return '{' .. table.concat(out, ',') .. '}'
    end
    error('cannot encode ' .. tv)
end

local function skipWs(s, i)
    local _, j = s:find('^[ \t\r\n]*', i)
    return j + 1
end

local decodeValue

local function decodeString(s, i)
    i = i + 1
    local out = {}
    while true do
        local c = s:sub(i, i)
        if c == '' then error('unterminated string') end
        if c == '"' then return table.concat(out), i + 1 end
        if c == '\\' then
            local e = s:sub(i + 1, i + 1)
            local map = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b',
                          f = '\f', n = '\n', r = '\r', t = '\t' }
            if map[e] then
                out[#out + 1] = map[e]
                i = i + 2
            elseif e == 'u' then
                local hex = s:sub(i + 2, i + 5)
                out[#out + 1] = utf8.char(tonumber(hex, 16))
                i = i + 6
            else
                error('bad escape ' .. e)
            end
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
end

decodeValue = function(s, i)
    i = skipWs(s, i)
    local c = s:sub(i, i)
    if c == '{' then
        local obj = {}
        i = skipWs(s, i + 1)
        if s:sub(i, i) == '}' then return obj, i + 1 end
        while true do
            local k
            k, i = decodeString(s, skipWs(s, i))
            i = skipWs(s, i)
            assert(s:sub(i, i) == ':', 'expected :')
            local v
            v, i = decodeValue(s, i + 1)
            obj[k] = v
            i = skipWs(s, i)
            local d = s:sub(i, i)
            if d == ',' then i = i + 1
            elseif d == '}' then return obj, i + 1
            else error('bad object at ' .. i) end
        end
    elseif c == '[' then
        local arr = {}
        i = skipWs(s, i + 1)
        if s:sub(i, i) == ']' then return arr, i + 1 end
        while true do
            local v
            v, i = decodeValue(s, i)
            arr[#arr + 1] = v
            i = skipWs(s, i)
            local d = s:sub(i, i)
            if d == ',' then i = i + 1
            elseif d == ']' then return arr, i + 1
            else error('bad array at ' .. i) end
        end
    elseif c == '"' then
        return decodeString(s, i)
    elseif s:sub(i, i + 3) == 'true' then return true, i + 4
    elseif s:sub(i, i + 4) == 'false' then return false, i + 5
    elseif s:sub(i, i + 3) == 'null' then return nil, i + 4
    else
        local num = s:match('^-?%d+%.?%d*[eE]?[+-]?%d*', i)
        assert(num and #num > 0, 'bad value at ' .. i .. ': ' .. s:sub(i, i + 10))
        return tonumber(num), i + #num
    end
end

function json.decode(s)
    local v = select(1, decodeValue(s, 1))
    return v
end

return json
