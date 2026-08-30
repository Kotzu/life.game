KTR = KTR or {}

KTR.Const = {
    RESOURCE = 'kotzu_trophy_room',
    ASSETS_RESOURCE = 'kotzu_mannequin_assets',
    MANNEQUIN_COLLECTION = 'mannequin',

    OUTFIT_SCHEMA = 2,

    -- display types (shared display abstraction, brief §14)
    DisplayType = {
        MANNEQUIN = 'mannequin',
        WEAPON_WALL = 'weapon_wall',
        WEAPON_STAND = 'weapon_stand',
        WEAPON_CASE = 'weapon_case',
        RARE_ITEM = 'rare_item',
        ACHIEVEMENT = 'achievement',
    },

    ScopeType = {
        WORLD = 'world',       -- absolute world transform
        SHELL = 'shell',       -- transform relative to a shell origin
        PROPERTY = 'property', -- transform relative to a property origin
    },

    Gender = { MALE = 'male', FEMALE = 'female' },
    Model = { male = 'mp_m_freemode_01', female = 'mp_f_freemode_01' },

    -- explicit error codes; clients render these, never a silent fallback
    Err = {
        MANIFEST_NOT_BUILT = 'MANIFEST_NOT_BUILT',
        OUTFIT_INCOMPATIBLE = 'OUTFIT_INCOMPATIBLE',
        OUTFIT_INVALID = 'OUTFIT_INVALID',
        NOT_ALLOWED = 'NOT_ALLOWED',
        NOT_FOUND = 'NOT_FOUND',
        RATE_LIMITED = 'RATE_LIMITED',
        LIMIT_REACHED = 'LIMIT_REACHED',
        BAD_INPUT = 'BAD_INPUT',
        SCOPE_MISMATCH = 'SCOPE_MISMATCH',
        TX_FAILED = 'TX_FAILED',
        ITEM_MISSING = 'ITEM_MISSING',
        DUPLICATE = 'DUPLICATE',
        INTERNAL = 'INTERNAL',
    },

    -- garment statuses from mannequin_manifest.json
    GarmentStatus = {
        SKIN_FREE = 'skin_free',
        CONVERTED = 'converted',
        PENDING = 'pending',
        PENDING_REVIEW = 'pending_review',
        INCOMPATIBLE = 'incompatible',
    },

    -- freemode component ids
    Comp = { HEAD = 0, BERD = 1, HAIR = 2, UPPR = 3, LOWR = 4, HAND = 5,
             FEET = 6, TEEF = 7, ACCS = 8, TASK = 9, DECL = 10, JBIB = 11 },
    -- base-skin carriers replaced by the mannequin body set
    BodyComponents = { 0, 2, 3, 5, 7 },
    -- SOURCE drawable index per component for the bare mannequin figure,
    -- identified visually from the converted base-game pieces:
    -- uppr 15 = bare torso+arms; lowr 14/15 = briefs + bare legs;
    -- feet: no barefoot male drawable exists in the base game (2 = the
    -- lowest-profile shoe, reads as a stylized mannequin foot), female 14 =
    -- bare feet. Components not listed fall back to source index 0.
    -- values: source drawable index, or { coll = '<source collection>',
    -- idx = n } for DLC pieces (resolved through the manifest)
    MannequinBase = {
        -- final look per user decision: ORIGINAL geometry (normal face,
        -- boxers kept); male feet = beach DLC bare feet, female = base bare
        male   = { [3] = 15, [4] = 14,
                   [6] = { coll = 'male_freemode_beach', idx = 0 } },
        female = { [3] = 15, [4] = 15, [6] = 14 },
    },
    AllComponents = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 },
    AllProps = { 0, 1, 2, 6, 7 },

    Permission = {
        OWNER = 'owner',
        CO_OWNER = 'co_owner',
        JOB = 'job',
        ADMIN = 'admin',
        VISITOR = 'visitor',
    },
}
