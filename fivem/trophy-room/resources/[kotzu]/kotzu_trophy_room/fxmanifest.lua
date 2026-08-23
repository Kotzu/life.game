fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kotzu_trophy_room'
description 'Trophy room display framework: full-body mannequins, weapon displays, rare items, achievements'
version '1.0.0'
author 'kotzu'

shared_scripts {
    'shared/constants.lua',
    'shared/config.lua',
    'shared/schemas.lua',
    'shared/locales.lua',
    'shared/rpc.lua',
    'bridge/init.lua',
}

client_scripts {
    'bridge/framework/qbox.lua',
    'bridge/framework/qbcore.lua',
    'bridge/framework/standalone.lua',
    'bridge/clothing/natives.lua',
    'bridge/clothing/illenium.lua',
    'bridge/clothing/rcore.lua',
    'bridge/target/qb.lua',
    'bridge/target/ox.lua',
    'bridge/target/fallback.lua',
    'bridge/housing/generic.lua',
    'client/manifest.lua',
    'client/mannequin.lua',
    'client/poses.lua',
    'client/renderers.lua',
    'client/streaming.lua',
    'client/placement.lua',
    'client/preview.lua',
    'client/interaction.lua',
    'client/nui.lua',
    'client/main.lua',
    'tests/client_harness.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/framework/qbox.lua',
    'bridge/framework/qbcore.lua',
    'bridge/framework/standalone.lua',
    'bridge/inventory/qb.lua',
    'bridge/inventory/ox.lua',
    'bridge/inventory/fallback.lua',
    'bridge/housing/generic.lua',
    'server/repository.lua',
    'server/permissions.lua',
    'server/validation.lua',
    'server/ratelimit.lua',
    'server/transactions.lua',
    'server/migrations.lua',
    'server/main.lua',
    'tests/server_harness.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
}

dependencies {
    'oxmysql',
}
