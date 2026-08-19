fx_version 'cerulean'
game 'gta5'

name 'kotzu_mannequin_assets'
description 'Streamed mannequin addon-clothing collection for mp_m/f_freemode_01 + manifest'
version '1.0.0'

-- Drawables/textures land in stream/ (built by tools/mannequin_pipeline on the
-- workstation; binaries are git-ignored and deployed alongside the resource).

files {
    'mannequin_manifest.json',
    'meta/mp_m_freemode_01_mannequin.meta',
    'meta/mp_f_freemode_01_mannequin.meta',
}

data_file 'SHOP_PED_APPAREL_META_FILE' 'meta/mp_m_freemode_01_mannequin.meta'
data_file 'SHOP_PED_APPAREL_META_FILE' 'meta/mp_f_freemode_01_mannequin.meta'
