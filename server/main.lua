-- chilllixhub-inject | server/main.lua
-- Server-side Lua injector.  For development / testing use only.
--
-- Commands (require Config.Permission ACE):
--   /inject_server  <lua code>           – execute on the server
--   /inject_client  <serverId> <lua code> – execute on one client
--   /inject_all     <lua code>           – execute on every connected client
--   /inject_file    <path>               – load a server-side file and execute it

local function log(msg)
    print(Config.LogPrefix .. ' ' .. msg)
end

--- Return true when the given source (player server-id or 0 for console) has
--- the required ACE permission.
local function hasPermission(source)
    if source == 0 then
        -- Console always has access.
        return true
    end
    return IsPlayerAceAllowed(tostring(source), Config.Permission)
end

--- Send a chat message back to the player (or print to console when source==0).
local function feedback(source, msg)
    if not Config.ChatFeedback then return end
    if source == 0 then
        print(Config.LogPrefix .. ' ' .. msg)
    else
        TriggerClientEvent('chat:addMessage', source, {
            color  = { 255, 200, 0 },
            multiline = true,
            args  = { Config.LogPrefix, msg },
        })
    end
end

--- Execute a Lua string in the server context and return ok, result.
local function execLua(code)
    local fn, compileErr = load(code, 'inject_server', 't', _ENV)
    if not fn then
        return false, 'Compile error: ' .. tostring(compileErr)
    end
    local ok, runtimeErr = pcall(fn)
    if not ok then
        return false, 'Runtime error: ' .. tostring(runtimeErr)
    end
    return true, 'OK'
end

-- /inject_server <code>
RegisterCommand('inject_server', function(source, args)
    if not hasPermission(source) then
        feedback(source, 'No permission.')
        return
    end

    local code = table.concat(args, ' ')
    if #code == 0 then
        feedback(source, 'Usage: /inject_server <lua code>')
        return
    end
    if #code > Config.MaxCodeLength then
        feedback(source, 'Code too long (max ' .. Config.MaxCodeLength .. ' chars).')
        return
    end

    log(('Player %s (id:%s) injecting server code: %s'):format(
        source == 0 and 'console' or GetPlayerName(tostring(source)),
        tostring(source), code))

    local ok, result = execLua(code)
    if ok then
        feedback(source, 'Server inject OK.')
    else
        feedback(source, 'Server inject FAILED: ' .. result)
        log('Inject failed: ' .. result)
    end
end, false)

-- /inject_client <serverId> <code>
RegisterCommand('inject_client', function(source, args)
    if not hasPermission(source) then
        feedback(source, 'No permission.')
        return
    end

    local targetId = tonumber(args[1])
    if not targetId then
        feedback(source, 'Usage: /inject_client <serverId> <lua code>')
        return
    end

    table.remove(args, 1)
    local code = table.concat(args, ' ')
    if #code == 0 then
        feedback(source, 'Usage: /inject_client <serverId> <lua code>')
        return
    end
    if #code > Config.MaxCodeLength then
        feedback(source, 'Code too long (max ' .. Config.MaxCodeLength .. ' chars).')
        return
    end

    if not GetPlayerName(tostring(targetId)) then
        feedback(source, 'Player ' .. targetId .. ' not found.')
        return
    end

    log(('Player %s (id:%s) injecting client code on target %s: %s'):format(
        source == 0 and 'console' or GetPlayerName(tostring(source)),
        tostring(source), targetId, code))

    TriggerClientEvent('chilllixhub-inject:exec', targetId, code)
    feedback(source, 'Sent to client ' .. targetId .. '.')
end, false)

-- /inject_all <code>
RegisterCommand('inject_all', function(source, args)
    if not hasPermission(source) then
        feedback(source, 'No permission.')
        return
    end

    local code = table.concat(args, ' ')
    if #code == 0 then
        feedback(source, 'Usage: /inject_all <lua code>')
        return
    end
    if #code > Config.MaxCodeLength then
        feedback(source, 'Code too long (max ' .. Config.MaxCodeLength .. ' chars).')
        return
    end

    log(('Player %s (id:%s) broadcasting client inject: %s'):format(
        source == 0 and 'console' or GetPlayerName(tostring(source)),
        tostring(source), code))

    TriggerClientEvent('chilllixhub-inject:exec', -1, code)
    feedback(source, 'Sent to all clients.')
end, false)

-- /inject_file <server-side file path>
RegisterCommand('inject_file', function(source, args)
    if not hasPermission(source) then
        feedback(source, 'No permission.')
        return
    end

    local path = args[1]
    if not path then
        feedback(source, 'Usage: /inject_file <path>')
        return
    end

    -- Only allow loading files inside the resource directory.
    -- Reject any path containing ".." sequences, backslashes, leading slashes,
    -- or null bytes to prevent path traversal on all supported platforms.
    if path:find('%.%.')
        or path:find('[\\]')
        or path:find('^[/\\]')
        or path:find('%z')
    then
        feedback(source, 'Invalid path: must be a relative path inside the resource folder with no ".." components.')
        log('Path traversal attempt blocked from ' .. tostring(source) .. ': ' .. path)
        return
    end

    local resourcePath = GetResourcePath(GetCurrentResourceName())
    -- Canonicalise the resource path (remove trailing slash/backslash if present).
    resourcePath = resourcePath:gsub('[/\\]+$', '')
    local fullPath = resourcePath .. '/' .. path

    -- Final guard: the resolved path must still start with the resource root.
    if fullPath:sub(1, #resourcePath) ~= resourcePath then
        feedback(source, 'Path escapes the resource directory.')
        log('Path escape attempt blocked: ' .. fullPath)
        return
    end

    log(('Player %s (id:%s) injecting file: %s'):format(
        source == 0 and 'console' or GetPlayerName(tostring(source)),
        tostring(source), fullPath))

    local fn, err = loadfile(fullPath)
    if not fn then
        feedback(source, 'File load error: ' .. tostring(err))
        log('File load error: ' .. tostring(err))
        return
    end

    local ok, runtimeErr = pcall(fn)
    if ok then
        feedback(source, 'File inject OK.')
    else
        feedback(source, 'File inject FAILED: ' .. tostring(runtimeErr))
        log('File inject failed: ' .. tostring(runtimeErr))
    end
end, false)
