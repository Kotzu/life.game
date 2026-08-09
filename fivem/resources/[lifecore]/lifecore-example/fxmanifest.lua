fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lifecore-example'
description 'Example resource showing how to build on the lifecore framework'
version '0.1.0'

shared_scripts {
    '@lifecore/config.lua',
    '@lifecore/shared/utils.lua',
}

server_script 'server/main.lua'
client_script 'client/main.lua'

dependency 'lifecore'
