ArchProofConfig = {
    -- Candidate A: name of a custom addon mannequin ped model, if one is installed
    -- for testing. Leave as-is when none exists; test A1 records SKIPPED and the
    -- decision falls back to documented constraints E1/E2 (see ADR-001).
    CandidateAModel = 'kotzu_mannequin_test',

    -- Freemode models under test (Candidate B/C)
    MaleModel = 'mp_m_freemode_01',
    FemaleModel = 'mp_f_freemode_01',

    -- Collection expected to be provided by kotzu_mannequin_assets once built.
    -- C1/B3 record NOT_YET_STREAMED (not FAIL) when the collection is absent so the
    -- proof can run before assets exist.
    MannequinCollection = 'mannequin',

    -- Freemode components that carry base skin (ADR-001 E4) + scalp
    SkinComponents = { 0, 2, 3, 4, 6 },

    -- Spawn offset for test peds, relative to the player
    SpawnOffset = vector3(1.5, 1.5, 0.0),

    -- Stability soak duration for B6 (ms)
    StabilitySoakMs = 60000,

    -- Set true to shorten B6 to 5s during iterative debugging
    QuickMode = false,
}
