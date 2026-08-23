-- oxmysql shim over the mariadb CLI (FXServer simulator).
-- Implements the MySQL.* surface the resource uses: query/single/scalar/
-- insert/update, each with .await plus fire-and-forget insert().

local SOCKET = os.getenv('FXSIM_MYSQL_SOCKET') or '/run/mysqld/mysqld.sock'
local DB = os.getenv('FXSIM_MYSQL_DB') or 'ktr_sim'

local function quoteParam(v)
    if v == nil then return 'NULL' end
    local t = type(v)
    if t == 'number' then return tostring(v) end
    if t == 'boolean' then return v and '1' or '0' end
    return "'" .. tostring(v):gsub('\\', '\\\\'):gsub("'", "\\'") .. "'"
end

local function bind(sql, params)
    if not params then return sql end
    local i = 0
    return (sql:gsub('%?', function()
        i = i + 1
        return quoteParam(params[i])
    end))
end

local counter = 0
local function run(sql)
    counter = counter + 1
    local tmp = os.tmpname()
    local f = assert(io.open(tmp, 'w'))
    f:write(sql)
    f:close()
    local cmd = ('mariadb --socket=%s --batch %s < %s 2>&1'):format(SOCKET, DB, tmp)
    local p = assert(io.popen(cmd))
    local out = p:read('a')
    local ok = p:close()
    os.remove(tmp)
    if not ok then
        error(('mysql error: %s\nsql: %s'):format(out, sql:sub(1, 400)))
    end
    return out
end

local function parseTsv(out)
    -- batch mode: header line then rows; multiple result sets are concatenated.
    -- We split blocks on repeated headers by tracking column counts per block.
    local blocks = {}
    local current = nil
    for line in out:gmatch('[^\n]+') do
        local fields = {}
        for field in (line .. '\t'):gmatch('([^\t]*)\t') do
            fields[#fields + 1] = field
        end
        if current == nil then
            current = { header = fields, rows = {} }
            blocks[#blocks + 1] = current
        elseif #fields ~= #current.header or current.expectHeader then
            current = { header = fields, rows = {} }
            blocks[#blocks + 1] = current
        else
            current.rows[#current.rows + 1] = fields
        end
    end
    return blocks
end

local function rowsFromBlock(block)
    local out = {}
    for _, r in ipairs(block.rows) do
        local row = {}
        for i, col in ipairs(block.header) do
            local v = r[i]
            if v == 'NULL' then v = nil
            elseif v and v:match('^-?%d+$') then v = tonumber(v)
            elseif v and v:match('^-?%d+%.%d+$') then v = tonumber(v) end
            row[col] = v
        end
        out[#out + 1] = row
    end
    return out
end

local function lastScalar(out)
    local lines = {}
    for line in out:gmatch('[^\n]+') do lines[#lines + 1] = line end
    local v = lines[#lines]
    return tonumber(v) or v
end

MySQL = {
    query = {}, single = {}, scalar = {}, insert = {}, update = {},
}

function MySQL.query.await(sql, params)
    local out = run(bind(sql, params))
    if out == '' then return {} end
    local blocks = parseTsv(out)
    return rowsFromBlock(blocks[#blocks])
end

function MySQL.single.await(sql, params)
    local rows = MySQL.query.await(sql, params)
    return rows[1]
end

function MySQL.scalar.await(sql, params)
    local out = run(bind(sql, params))
    if out == '' then return nil end
    local blocks = parseTsv(out)
    local rows = blocks[#blocks].rows
    local v = rows[1] and rows[1][1]
    if v == 'NULL' then return nil end
    return tonumber(v) or v
end

function MySQL.insert.await(sql, params)
    local out = run(bind(sql, params) .. ';\nSELECT LAST_INSERT_ID();')
    return lastScalar(out)
end

function MySQL.update.await(sql, params)
    local out = run(bind(sql, params) .. ';\nSELECT ROW_COUNT();')
    return lastScalar(out)
end

setmetatable(MySQL.insert, { __call = function(_, sql, params)
    MySQL.insert.await(sql, params)
end })

setmetatable(MySQL.update, { __call = function(_, sql, params)
    MySQL.update.await(sql, params)
end })

return MySQL
