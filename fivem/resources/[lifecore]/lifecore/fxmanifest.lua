fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lifecore'
author 'life.game'
description 'LifeCore - a lightweight FiveM roleplay framework core'
version '0.1.0'

shared_scripts {
    'config.lua',
    'shared/utils.lua',
    'shared/services.lua',
    'shared/jobs.lua',
    'shared/items.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/player.lua',
    'server/functions.lua',
    'server/callbacks.lua',
    'server/main.lua',
    'server/commands.lua',
}

client_scripts {
    'client/functions.lua',
    'client/callbacks.lua',
    'client/main.lua',
}

dependency 'oxmysql'
