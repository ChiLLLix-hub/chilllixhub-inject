fx_version 'cerulean'
game 'gta5'

author 'ChiLLLix-hub'
description 'Lua Injector for FiveM – testing and development use only'
version '1.0.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

shared_scripts {
    'shared/config.lua',
}

server_scripts {
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}
