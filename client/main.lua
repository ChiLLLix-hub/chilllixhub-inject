-- chilllixhub-inject | client/main.lua
-- Client-side Lua injector.  For development / testing use only.
--
-- Commands (local, require Config.Permission ACE):
--   /inject_local <lua code>  – execute a Lua snippet on this client
--
-- Network events (triggered by server):
--   chilllixhub-inject:exec   – execute a Lua snippet on this client

local function log(msg)
    print(Config.LogPrefix .. ' ' .. msg)
end

--- Send a chat feedback message locally.
local function feedback(msg)
    if not Config.ChatFeedback then return end
    TriggerEvent('chat:addMessage', {
        color     = { 255, 200, 0 },
        multiline = true,
        args      = { Config.LogPrefix, msg },
    })
end

--- Execute a Lua string in the client context and return ok, result.
local function execLua(code)
    local fn, compileErr = load(code, 'inject_client', 't', _ENV)
    if not fn then
        return false, 'Compile error: ' .. tostring(compileErr)
    end
    local ok, runtimeErr = pcall(fn)
    if not ok then
        return false, 'Runtime error: ' .. tostring(runtimeErr)
    end
    return true, 'OK'
end

-- /inject_local <code>  (client-side command, only for the local player)
-- NOTE: FiveM client-side ACE checks cannot be fully enforced from the client.
-- This command is intentionally unrestricted locally because it only affects
-- the player running it (no server state is modified).  Restrict server-side
-- commands (/inject_client, /inject_all) via Config.Permission instead.
RegisterCommand('inject_local', function(source, args)
    local code = table.concat(args, ' ')
    if #code == 0 then
        feedback('Usage: /inject_local <lua code>')
        return
    end
    if #code > Config.MaxCodeLength then
        feedback('Code too long (max ' .. Config.MaxCodeLength .. ' chars).')
        return
    end

    log('Local inject: ' .. code)

    local ok, result = execLua(code)
    if ok then
        feedback('Local inject OK.')
    else
        feedback('Local inject FAILED: ' .. result)
        log('Inject failed: ' .. result)
    end
end, false)

-- Triggered by server via /inject_client or /inject_all.
-- In FiveM, only the server can trigger client events via TriggerClientEvent,
-- so this event cannot be spoofed by other clients.
AddEventHandler('chilllixhub-inject:exec', function(code)
    if type(code) ~= 'string' then
        log('Received non-string code, ignoring.')
        return
    end
    if #code > Config.MaxCodeLength then
        log('Received code exceeds MaxCodeLength, ignoring.')
        return
    end

    log('Remote inject received.')

    local ok, result = execLua(code)
    if ok then
        log('Remote inject OK.')
    else
        log('Remote inject FAILED: ' .. result)
    end
end)
