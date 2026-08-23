KTR = KTR or {}

KTR.Config = {
    Debug = false,
    Locale = 'en',

    -- ------------------------------------------------------------ streaming
    Streaming = {
        SpawnRadius = 45.0,      -- displays materialize inside this radius
        DespawnRadius = 55.0,    -- hysteresis: torn down outside this radius
        ScanIntervalMs = 1000,   -- registry scan cadence (no Wait(0) loops)
        MaxVisibleDisplays = 50, -- hard client cap; nearest win
        SpawnBatchSize = 4,      -- entities created per scan tick, to smooth spikes
        Collision = true,        -- mannequin collision (configurable, brief §9)
    },

    -- ------------------------------------------------------------ placement
    Placement = {
        MaxDistance = 12.0,      -- max distance from player to placed display
        MoveStep = 0.05,
        MoveStepFine = 0.01,
        RotStep = 5.0,
        RotStepFine = 1.0,
        SnapIncrements = { 0.0, 0.25, 0.5, 1.0 },   -- 0.0 = free
        WallAlignTypes = { weapon_wall = true },     -- types that raycast to walls
        GroundAlign = true,
    },

    -- ------------------------------------------------------------- limits
    Limits = {
        DisplaysPerScope = 50,       -- per property/shell instance
        DisplaysPerOwner = 100,      -- global per citizen
        OutfitPayloadBytes = 16384,  -- serialized outfit size cap (server enforced)
        LabelLength = 48,
        DescriptionLength = 256,
    },

    -- ---------------------------------------------------------- rate limits
    RateLimit = {
        -- events per rolling minute, per player
        place = 10, update = 30, delete = 10, query = 30,
        capture_outfit = 12, weapon_tx = 6, preview = 12,
    },

    -- --------------------------------------------------------------- poses
    -- Every dict+clip below was verified to EXIST against the DurtyFree
    -- animDictsCompact dump (20,179 dicts); scenarios verified against
    -- scenariosCompact. `genderDict` overrides `dict` per gender where the
    -- game ships male/female-specific clips (poses.lua picks by ped model).
    -- Priority when applying: genderDict → dict → scenario → fallback*.
    -- Labels/order mirror the design concept (docs/design/concept-target.png).
    Poses = {
        { id = 'neutral',     label = 'Default Stand',      anim = 'idle', flag = 1,
          genderDict = { male = 'anim@heists@heist_corona@team_idles@male_a',
                         female = 'anim@heists@heist_corona@team_idles@female_a' },
          fallbackScenario = 'WORLD_HUMAN_STAND_IMPATIENT' },
        { id = 'arms_crossed',label = 'Arms Crossed',       dict = 'mini@strip_club@idles@bouncer@base',
          anim = 'base', flag = 1 },
        { id = 'hands_back',  label = 'Hands Behind Back',  dict = 'anim@amb@casino@valet_scenario@pose_d@',
          anim = 'base_a_m_y_vinewood_01', flag = 1,
          fallbackScenario = 'WORLD_HUMAN_GUARD_STAND' },
        { id = 'hands_on_belt', label = 'Hands On Belt',    dict = 'amb@world_human_cop_idles@male@base',
          anim = 'base', flag = 1,
          fallbackScenario = 'WORLD_HUMAN_COP_IDLES' },
        { id = 'attention',   label = 'Military Attention', scenario = 'WORLD_HUMAN_GUARD_STAND_ARMY' },
        { id = 'at_ease',     label = 'Military At Ease',   scenario = 'WORLD_HUMAN_GUARD_STAND' },
        { id = 'guard',       label = 'Security Guard',     scenario = 'WORLD_HUMAN_GUARD_PATROL',
          fallbackScenario = 'WORLD_HUMAN_COP_IDLES' },
        { id = 'inspect',     label = 'Inspecting',         scenario = 'WORLD_HUMAN_CLIPBOARD',
          fallbackScenario = 'WORLD_HUMAN_INSPECT_STAND' },
        { id = 'relaxed',     label = 'Relaxed',            dict = 'amb@world_human_hang_out_street@male_c@base',
          anim = 'base', flag = 1,
          fallbackScenario = 'WORLD_HUMAN_STAND_IMPATIENT' },
        { id = 'tpose',       label = 'T-Pose',             dict = 'nm@hands', anim = 'front',
          flag = 2, debugOnly = true },
    },
    DefaultPose = 'neutral',

    -- ----------------------------------------------------------- platforms
    Platforms = {
        { id = 'none',      label = 'No stand',        model = nil },
        { id = 'round',     label = 'Round base',      model = 'prop_mp_base_marker' },
        { id = 'plinth',    label = 'Display plinth',  model = 'prop_construcionlamp_01' },
    },

    -- -------------------------------------------------------- weapon display
    Weapons = {
        WallOffsetProbe = 1.5,        -- raycast length for wall mounts
        CaseModel = 'prop_display_case_01',
        StandModel = 'prop_weapon_rack_01', -- validated at runtime; config per server
        RequireInventoryBridge = true, -- refuse weapon displays without a working bridge
    },

    -- ------------------------------------------------------------- housing
    Housing = {
        -- Generic bridge contract (brief §16). Any housing script can integrate by
        -- calling the exports/events documented in bridge/housing/generic.lua.
        -- TestShells lets the acceptance suite run without a housing product.
        TestShells = {
            {
                shellId = 'test_shell_a',
                origin = vector4(-1000.0, -1000.0, 500.0, 0.0),
                bucket = 100,
            },
            {
                shellId = 'test_shell_b',
                origin = vector4(-1000.0, -1000.0, 500.0, 0.0),
                bucket = 101,
            },
        },
    },

    -- ---------------------------------------------------- demo room layout
    -- A ready-made trophy-room arrangement (transforms are shell/property-LOCAL,
    -- i.e. relative to the room origin). Used by /kmq:demo_layout to populate a
    -- shell for acceptance test T8 and for design previews. Poses reference the
    -- verified pose ids above.
    DemoLayout = {
        { displayType = 'mannequin', gender = 'male',   poseId = 'attention',
          platform = 'plinth', label = 'Uniformă patrulare',
          transform = { x = -2.0, y = 2.0, z = 0.0, heading = 180.0 } },
        { displayType = 'mannequin', gender = 'female', poseId = 'at_ease',
          platform = 'plinth', label = 'Uniformă ceremonie',
          transform = { x = 0.0,  y = 2.0, z = 0.0, heading = 180.0 } },
        { displayType = 'mannequin', gender = 'male',   poseId = 'arms_crossed',
          platform = 'round',  label = 'Ținută tactică',
          transform = { x = 2.0,  y = 2.0, z = 0.0, heading = 180.0 } },
        { displayType = 'weapon_wall',  label = 'Armă de colecție',
          transform = { x = -2.5, y = 3.4, z = 1.3, heading = 0.0 } },
        { displayType = 'weapon_stand', label = 'Pistol de serviciu',
          transform = { x = 2.5,  y = 3.2, z = 0.0, heading = 90.0 } },
    },

    -- ------------------------------------------------------------ interaction
    Interaction = {
        TargetDistance = 2.2,
        AllowVisitorTryOn = true,      -- temporary try-on (auto-restore)
        TryOnSeconds = 60,
        AllowVisitorEquip = false,     -- permanent equip needs explicit permission
    },

    -- --------------------------------------------------------------- admin
    AdminAce = 'kotzu.trophy.admin',   -- ace permission for admin overrides
    DevCommands = true,                -- /kmq:* harness (disable on live)
}
