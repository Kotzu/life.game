-- Player object factory. Each connected, loaded player gets one of these.
-- All mutating methods mark the player dirty and sync the relevant slice of
-- state to that player's client via the lifecore:player:update event.

LifePlayer = {}

---@param source number server id
---@param identifier string primary identifier (license/steam/discord)
---@param row table|nil row from the players table, nil for a brand new player
---@return table player
function LifePlayer.new(source, identifier, row)
    local self = {}

    self.source = source
    self.identifier = identifier
    self.name = GetPlayerName(source) or 'Unknown'

    if row then
        self.money = json.decode(row.money)
        self.job = json.decode(row.job)
        self.inventory = json.decode(row.inventory)
        self.metadata = json.decode(row.metadata)
        self.position = json.decode(row.position)
    else
        self.money = { cash = Config.StartingCash, bank = Config.StartingBank }
        self.job = { name = Config.DefaultJob, grade = Config.DefaultJobGrade }
        self.inventory = {}
        self.metadata = { hunger = 100, thirst = 100 }
        self.position = {
            x = Config.DefaultSpawn.x,
            y = Config.DefaultSpawn.y,
            z = Config.DefaultSpawn.z,
            heading = Config.DefaultSpawn.w,
        }
    end

    -- Repair references to job definitions that were removed from shared/jobs.lua
    if not LifeJobs[self.job.name] or not LifeJobs[self.job.name].grades[self.job.grade] then
        self.job = { name = Config.DefaultJob, grade = Config.DefaultJobGrade }
    end

    local function sync(key, value)
        TriggerClientEvent('lifecore:player:update', self.source, key, value)
    end

    --- Get the amount held in a money account.
    ---@param account string 'cash' | 'bank'
    ---@return number
    function self.GetMoney(account)
        return self.money[account] or 0
    end

    --- Add money to an account. Returns false for invalid input.
    ---@param account string
    ---@param amount number
    ---@return boolean
    function self.AddMoney(account, amount)
        amount = math.floor(tonumber(amount) or 0)
        if amount <= 0 or self.money[account] == nil then return false end
        self.money[account] = self.money[account] + amount
        sync('money', self.money)
        return true
    end

    --- Remove money from an account. Fails if the balance is insufficient.
    ---@param account string
    ---@param amount number
    ---@return boolean
    function self.RemoveMoney(account, amount)
        amount = math.floor(tonumber(amount) or 0)
        if amount <= 0 or (self.money[account] or 0) < amount then return false end
        self.money[account] = self.money[account] - amount
        sync('money', self.money)
        return true
    end

    --- Set a player's job. Returns false if the job or grade doesn't exist.
    ---@param name string job name from shared/jobs.lua
    ---@param grade number
    ---@return boolean
    function self.SetJob(name, grade)
        grade = tonumber(grade) or 0
        local jobDef = LifeJobs[name]
        if not jobDef or not jobDef.grades[grade] then return false end
        self.job = { name = name, grade = grade }
        sync('job', self.job)
        TriggerEvent('lifecore:server:jobChanged', self.source, name, grade)
        return true
    end

    --- Get the full job info (definition merged with the player's grade).
    ---@return table
    function self.GetJob()
        local def = LifeJobs[self.job.name]
        local gradeDef = def.grades[self.job.grade]
        return {
            name = self.job.name,
            label = def.label,
            grade = self.job.grade,
            gradeLabel = gradeDef.label,
            salary = gradeDef.salary,
            isboss = gradeDef.isboss or false,
        }
    end

    --- Count how many of an item the player carries.
    ---@param item string
    ---@return number
    function self.GetItemCount(item)
        for _, slot in ipairs(self.inventory) do
            if slot.name == item then return slot.count end
        end
        return 0
    end

    --- Add an item to the inventory. Returns false for unknown items.
    ---@param item string key from shared/items.lua
    ---@param count number|nil defaults to 1
    ---@return boolean
    function self.AddItem(item, count)
        count = math.floor(tonumber(count) or 1)
        local def = LifeItems[item]
        if not def or count <= 0 then return false end
        if def.stack then
            for _, slot in ipairs(self.inventory) do
                if slot.name == item then
                    slot.count = slot.count + count
                    sync('inventory', self.inventory)
                    return true
                end
            end
        end
        for _ = 1, (def.stack and 1 or count) do
            self.inventory[#self.inventory + 1] = {
                name = item,
                count = def.stack and count or 1,
            }
        end
        sync('inventory', self.inventory)
        return true
    end

    --- Remove an item from the inventory. Fails if the player has too few.
    ---@param item string
    ---@param count number|nil defaults to 1
    ---@return boolean
    function self.RemoveItem(item, count)
        count = math.floor(tonumber(count) or 1)
        if count <= 0 or self.GetItemCount(item) < count then return false end
        for i = #self.inventory, 1, -1 do
            local slot = self.inventory[i]
            if slot.name == item then
                local take = math.min(slot.count, count)
                slot.count = slot.count - take
                count = count - take
                if slot.count == 0 then table.remove(self.inventory, i) end
                if count == 0 then break end
            end
        end
        sync('inventory', self.inventory)
        return true
    end

    --- Read a metadata value (hunger, thirst, or anything a resource stores).
    ---@param key string
    function self.GetMetadata(key)
        return self.metadata[key]
    end

    --- Write a metadata value and sync it.
    ---@param key string
    ---@param value any json-encodable
    function self.SetMetadata(key, value)
        self.metadata[key] = value
        sync('metadata', self.metadata)
    end

    --- Snapshot the player's state for sending to the client on load.
    ---@return table
    function self.GetClientData()
        return {
            identifier = self.identifier,
            name = self.name,
            money = self.money,
            job = self.job,
            inventory = self.inventory,
            metadata = self.metadata,
            position = self.position,
        }
    end

    --- Persist the player to the database. `cb` fires after the write.
    ---@param cb function|nil
    function self.Save(cb)
        local ped = GetPlayerPed(self.source)
        if ped and ped ~= 0 then
            local coords = GetEntityCoords(ped)
            self.position = {
                x = LifeUtils.Round(coords.x, 2),
                y = LifeUtils.Round(coords.y, 2),
                z = LifeUtils.Round(coords.z, 2),
                heading = LifeUtils.Round(GetEntityHeading(ped), 2),
            }
        end
        MySQL.update(
            'UPDATE players SET name = ?, money = ?, job = ?, inventory = ?, metadata = ?, position = ? WHERE identifier = ?',
            {
                self.name,
                json.encode(self.money),
                json.encode(self.job),
                json.encode(self.inventory),
                json.encode(self.metadata),
                json.encode(self.position),
                self.identifier,
            },
            cb
        )
    end

    return self
end
