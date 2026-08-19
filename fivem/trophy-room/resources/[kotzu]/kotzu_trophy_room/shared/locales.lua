KTR = KTR or {}

local Locales = {
    en = {
        display = 'Display',
        mannequin = 'Mannequin',
        inspect = 'Inspect',
        change_outfit = 'Change outfit',
        change_pose = 'Change pose',
        rename = 'Rename',
        move = 'Move',
        remove = 'Remove',
        retrieve_outfit = 'Retrieve outfit',
        preview_outfit = 'Preview outfit',
        try_outfit = 'Try outfit (temporary)',
        equip_outfit = 'Equip outfit',
        retrieve_weapon = 'Retrieve weapon',
        placement_help = 'Arrows: move · Q/E: rotate · Shift: fine · G: ground snap · X: collision · Enter: confirm · Backspace: cancel',
        placed = 'Display placed',
        removed = 'Display removed',
        updated = 'Display updated',
        outfit_captured = 'Outfit captured to mannequin',
        outfit_restored = 'Your outfit was restored',
        err_MANIFEST_NOT_BUILT = 'Mannequin assets are not built yet (manifest v0)',
        err_OUTFIT_INCOMPATIBLE = 'This outfit contains unconverted skin-bearing garments and cannot be displayed',
        err_OUTFIT_INVALID = 'Invalid outfit data',
        err_NOT_ALLOWED = 'You are not allowed to do that',
        err_NOT_FOUND = 'Display not found',
        err_RATE_LIMITED = 'Slow down',
        err_LIMIT_REACHED = 'Display limit reached',
        err_BAD_INPUT = 'Invalid request',
        err_SCOPE_MISMATCH = 'You are not in the right place for that display',
        err_TX_FAILED = 'Transaction failed — nothing was changed',
        err_ITEM_MISSING = 'Required item not found in your inventory',
        err_INTERNAL = 'Internal error — check server console',
    },
}

function KTR.L(key, ...)
    local pack = Locales[KTR.Config.Locale] or Locales.en
    local s = pack[key] or Locales.en[key] or key
    if select('#', ...) > 0 then return s:format(...) end
    return s
end

function KTR.ErrText(code)
    return KTR.L('err_' .. tostring(code))
end
