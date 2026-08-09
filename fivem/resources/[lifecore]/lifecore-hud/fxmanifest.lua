fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lifecore-hud'
description 'Modern NUI HUD for the lifecore framework: status bars, money, toast notifications'
version '0.1.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

shared_script '@lifecore/shared/jobs.lua'
client_script 'client/main.lua'

dependency 'lifecore'
