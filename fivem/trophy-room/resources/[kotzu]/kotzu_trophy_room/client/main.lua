--[[ Client entry: bridge resolution, initial scope sync, user commands. ]]

CreateThread(function()
    -- resolve bridges early so their detection is logged at startup
    KTR.Bridge.Get('framework')
    KTR.Bridge.Get('clothing')
    KTR.Bridge.Get('target')
    KTR.Bridge.Get('housing')
    KTRC.Manifest.Load()

    -- initial registry sync (retry until server repo is ready)
    while not KTRC.Streaming.RequestScope() do
        Wait(2000)
    end
end)

-- resync after (re)spawn — covers reconnect and bucket changes
AddEventHandler('playerSpawned', function()
    Wait(1000)
    KTRC.Streaming.RequestScope()
end)

RegisterCommand('trophyroom', function()
    if KTRC.Placement.IsActive() then return end
    KTRC.UI.OpenWizard()
end, false)

RegisterKeyMapping('trophyroom', 'Open trophy room placement', 'keyboard', 'F7')
