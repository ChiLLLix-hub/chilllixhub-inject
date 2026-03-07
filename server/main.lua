-- chilllixhub-inject | server/main.lua
-- Server-side Lua injector.  For development / testing use only.
--
-- Commands (require Config.Permission ACE):
--   /inject_server   <lua code>            – execute on the server
--   /inject_client   <serverId> <lua code> – execute on one client
--   /inject_all      <lua code>            – execute on every connected client
--   /inject_file     <path>                – load a server-side file and execute it
--
-- Inspection commands (require Config.Permission ACE):
--   /inject_history  [page]  – list recent injections (most-recent first)
--   /inject_show     <id>    – show code and registered handlers for one injection
--   /inject_triggers         – list every event handler registered by injected code
--   /inject_active           – show the injection that is currently executing

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

-- ─── Injection history ───────────────────────────────────────────────────────

local InjectHistory    = {}   -- array of { id, time, type, source, code, handlers }
local nextInjectId     = 1
local currentlyExecuting = nil   -- set while an inject pcall is in progress
local lastExecuted       = nil   -- the most-recently started injection record

--- Append an injection record to the history and return it.
local function newRecord(injectType, source, code)
    local record = {
        id       = nextInjectId,
        time     = os.date('%H:%M:%S'),
        type     = injectType,   -- 'server' | 'client' | 'all' | 'file'
        source   = source == 0 and 'console' or tostring(source),
        code     = code,
        handlers = {},           -- event/net-event names registered during execution
    }
    InjectHistory[#InjectHistory + 1] = record
    if #InjectHistory > Config.HistoryMax then
        table.remove(InjectHistory, 1)
    end
    nextInjectId = nextInjectId + 1
    return record
end

--- Return the record with the given numeric id, or nil.
local function findRecord(id)
    for _, r in ipairs(InjectHistory) do
        if r.id == id then return r end
    end
    return nil
end

-- ─── Execution ───────────────────────────────────────────────────────────────

--- Execute a Lua string in the given environment (defaults to _ENV).
local function execLuaInEnv(code, env)
    local fn, compileErr = load(code, 'inject_server', 't', env or _ENV)
    if not fn then
        return false, 'Compile error: ' .. tostring(compileErr)
    end
    local ok, runtimeErr = pcall(fn)
    if not ok then
        return false, 'Runtime error: ' .. tostring(runtimeErr)
    end
    return true, 'OK'
end

--- Execute a Lua string in the server context and return ok, result.
local function execLua(code) return execLuaInEnv(code, _ENV) end

--- Execute code while tracking event-handler registrations into `record`.
--- When Config.TrackTriggers is false (or record is nil) falls back to execLua.
local function execLuaTracked(code, record)
    if not (Config.TrackTriggers and record) then
        return execLua(code)
    end

    local function trackHandler(name)
        for _, h in ipairs(record.handlers) do
            if h == name then return end  -- deduplicate
        end
        record.handlers[#record.handlers + 1] = name
    end

    -- Proxy environment: intercepts AddEventHandler / RegisterNetEvent calls
    -- made by the injected snippet so we can record them.  All other lookups
    -- and assignments pass through to the real _ENV.
    local proxy = setmetatable({
        AddEventHandler = function(name, ...)
            trackHandler(name)
            return AddEventHandler(name, ...)
        end,
        RegisterNetEvent = function(name, ...)
            trackHandler(name)
            return RegisterNetEvent(name, ...)
        end,
    }, { __index = _ENV, __newindex = _ENV })

    lastExecuted       = record
    currentlyExecuting = record
    local ok, result   = execLuaInEnv(code, proxy)
    currentlyExecuting = nil

    return ok, result
end

-- ─── Original injection commands ─────────────────────────────────────────────

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

    local record = newRecord('server', source, code)
    local ok, result = execLuaTracked(code, record)
    if ok then
        feedback(source, ('Server inject OK. [#%d]'):format(record.id))
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

    local record = newRecord('client', source, code)
    TriggerClientEvent('chilllixhub-inject:exec', targetId, code)
    feedback(source, ('Sent to client %d. [#%d]'):format(targetId, record.id))
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

    local record = newRecord('all', source, code)
    TriggerClientEvent('chilllixhub-inject:exec', -1, code)
    feedback(source, ('Sent to all clients. [#%d]'):format(record.id))
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

    -- Read the raw source for the history record (best-effort).
    -- Falls back to storing the file path when the file cannot be re-read.
    local fileSource = path
    local fh = io.open(fullPath, 'r')
    if fh then fileSource = fh:read('*a'); fh:close() end

    local record = newRecord('file', source, fileSource)
    lastExecuted       = record
    currentlyExecuting = record
    local ok, runtimeErr = pcall(fn)
    currentlyExecuting = nil

    if ok then
        feedback(source, ('File inject OK. [#%d]'):format(record.id))
    else
        feedback(source, 'File inject FAILED: ' .. tostring(runtimeErr))
        log('File inject failed: ' .. tostring(runtimeErr))
    end
end, false)

-- ─── Inspection commands ──────────────────────────────────────────────────────

-- /inject_history [page]
-- Lists recent server-side injections, most-recent first.
RegisterCommand('inject_history', function(source, args)
    if not hasPermission(source) then
        feedback(source, 'No permission.')
        return
    end

    local page     = math.max(1, tonumber(args[1]) or 1)
    local pageSize = Config.HistoryPage
    local total    = #InjectHistory

    if total == 0 then
        feedback(source, 'No injection history recorded yet.')
        return
    end

    -- Display most-recent first.
    local reversed = {}
    for i = total, 1, -1 do reversed[#reversed + 1] = InjectHistory[i] end

    local pages    = math.ceil(total / pageSize)
    page           = math.min(page, pages)
    local startIdx = (page - 1) * pageSize + 1
    local endIdx   = math.min(startIdx + pageSize - 1, total)

    feedback(source, ('Injection history (page %d/%d):'):format(page, pages))
    for i = startIdx, endIdx do
        local r       = reversed[i]
        local preview = r.code:sub(1, 60):gsub('\n', ' ')
        if #r.code > 60 then preview = preview .. '…' end
        feedback(source, (' #%-3d  %s  %-6s  src:%-8s  %s'):format(
            r.id, r.time, r.type, r.source, preview))
    end
    if pages > 1 then
        feedback(source, ('Page %d of %d — use /inject_history <page> to navigate.'):format(page, pages))
    end
end, false)

-- /inject_show <id>
-- Shows the full code and registered event-handler names for one record.
RegisterCommand('inject_show', function(source, args)
    if not hasPermission(source) then
        feedback(source, 'No permission.')
        return
    end

    local id = tonumber(args[1])
    if not id then
        feedback(source, 'Usage: /inject_show <id>')
        return
    end

    local r = findRecord(id)
    if not r then
        feedback(source, ('No injection record with id %d found.'):format(id))
        return
    end

    feedback(source, ('Injection #%d — type:%s  time:%s  src:%s'):format(
        r.id, r.type, r.time, r.source))
    feedback(source, 'Code:')
    -- Split into lines for readability (chat wraps long lines anyway).
    for line in (r.code .. '\n'):gmatch('([^\n]*)\n') do
        feedback(source, '  ' .. line)
    end
    if #r.handlers > 0 then
        feedback(source, 'Registered handlers: ' .. table.concat(r.handlers, ', '))
    else
        feedback(source, 'Registered handlers: (none)')
    end
end, false)

-- /inject_triggers
-- Lists every event handler registered by any injection in the history.
RegisterCommand('inject_triggers', function(source, args)
    if not hasPermission(source) then
        feedback(source, 'No permission.')
        return
    end

    local found = false
    for _, r in ipairs(InjectHistory) do
        if #r.handlers > 0 then
            found = true
            feedback(source, (' #%d (%s/%s)  handlers: %s'):format(
                r.id, r.time, r.type, table.concat(r.handlers, ', ')))
        end
    end
    if not found then
        feedback(source, 'No event handlers have been registered by injected code yet.')
    end
end, false)

-- /inject_active
-- Shows which injection is currently executing (set during pcall).
-- Also shows the most-recently started injection for convenience.
RegisterCommand('inject_active', function(source, args)
    if not hasPermission(source) then
        feedback(source, 'No permission.')
        return
    end

    if currentlyExecuting then
        local r = currentlyExecuting
        feedback(source, ('Currently executing: #%d  type:%s  time:%s  src:%s'):format(
            r.id, r.type, r.time, r.source))
        feedback(source, 'Code: ' .. r.code:sub(1, 120))
    else
        feedback(source, 'No injection is executing right now.')
    end

    if lastExecuted then
        local r = lastExecuted
        feedback(source, ('Last executed: #%d  type:%s  time:%s  src:%s  — /inject_show %d for full code'):format(
            r.id, r.type, r.time, r.source, r.id))
    else
        feedback(source, 'No injection has run yet in this session.')
    end
end, false)

