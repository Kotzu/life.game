--[[
    Idempotent SQL migrations, applied on resource start in order. Each file in
    sql/ is tracked in kotzu_schema_migrations; already-applied files are
    skipped (and every statement is itself IF NOT EXISTS-safe as a second layer).
]]

KTRS = KTRS or {}
KTRS.MigrationsReady = false

local MIGRATIONS = {
    '001_init.sql',
    '002_tx_locks.sql',
    '003_audit.sql',
}

local function splitStatements(sqlText)
    local statements = {}
    for stmt in sqlText:gmatch('([^;]+);') do
        local trimmed = stmt:gsub('%-%-[^\n]*', ''):gsub('^%s+', ''):gsub('%s+$', '')
        if #trimmed > 0 then statements[#statements + 1] = trimmed end
    end
    return statements
end

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `kotzu_schema_migrations` (
        `name` VARCHAR(128) NOT NULL,
        `applied_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`name`)
    ) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4]])

    for _, file in ipairs(MIGRATIONS) do
        local applied = MySQL.scalar.await(
            'SELECT 1 FROM kotzu_schema_migrations WHERE name = ?', { file })
        if not applied then
            local text = LoadResourceFile(GetCurrentResourceName(), 'sql/' .. file)
            if not text then
                print(('[kotzu_trophy] FATAL: migration file sql/%s missing'):format(file))
                return
            end
            for _, stmt in ipairs(splitStatements(text)) do
                MySQL.query.await(stmt)
            end
            MySQL.insert.await('INSERT INTO kotzu_schema_migrations (name) VALUES (?)', { file })
            print(('[kotzu_trophy] migration applied: %s'):format(file))
        end
    end
    KTRS.MigrationsReady = true
    TriggerEvent('kotzu_trophy:server:migrationsReady')
end)
