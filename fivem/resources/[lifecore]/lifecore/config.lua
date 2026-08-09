Config = {}

-- General
Config.Debug = false
Config.Locale = 'en'

-- Player defaults
Config.DefaultSpawn = vector4(-1035.71, -2731.87, 12.86, 0.0) -- LSIA
Config.StartingCash = 500
Config.StartingBank = 5000
Config.DefaultJob = 'unemployed'
Config.DefaultJobGrade = 0

-- Persistence
Config.SaveInterval = 5 * 60 * 1000 -- autosave every 5 minutes (ms)

-- Identity
Config.IdentifierType = 'license' -- 'license' | 'steam' | 'discord'

-- Status (hunger/thirst tick)
Config.StatusEnabled = true
Config.StatusTickRate = 60 * 1000 -- every minute (ms)
Config.HungerPerTick = 1
Config.ThirstPerTick = 2
