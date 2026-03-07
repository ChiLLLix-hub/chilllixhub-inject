-- chilllixhub-inject | client/main.lua
-- Client-side Lua injector.  For development / testing use only.
--
-- Commands (local, unrestricted – only affects the local player):
--   /inject_local            <lua code>  – execute a Lua snippet on this client
--
-- Network events (triggered by server):
--   chilllixhub-inject:exec              – execute a Lua snippet on this client
--
-- Inspection commands (local):
--   /inject_history_local    [page]      – list recent local injections
--   /inject_show_local       <id>        – show code & handlers for one injection
--   /inject_triggers_local               – list event handlers registered by injections
--   /inject_active_local                 – show the injection currently executing

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

-- ─── Injection history ───────────────────────────────────────────────────────

local InjectHistory      = {}  -- array of { id, time, type, code, handlers }
local nextInjectId       = 1
local currentlyExecuting = nil   -- set while an inject pcall is in progress
local lastExecuted       = nil   -- the most-recently started injection record

--- Append an injection record to the history and return it.
local function newRecord(injectType, code)
    local record = {
        id       = nextInjectId,
        time     = os.date('%H:%M:%S'),
        type     = injectType,   -- 'local' | 'remote'
        code     = code,
        handlers = {},           -- event names registered during execution
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
    local fn, compileErr = load(code, 'inject_client', 't', env or _ENV)
    if not fn then
        return false, 'Compile error: ' .. tostring(compileErr)
    end
    local ok, runtimeErr = pcall(fn)
    if not ok then
        return false, 'Runtime error: ' .. tostring(runtimeErr)
    end
    return true, 'OK'
end

--- Execute a Lua string in the client context and return ok, result.
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

    -- Proxy environment: intercepts AddEventHandler calls made by the injected
    -- snippet so we can record them.
    local proxy = setmetatable({
        AddEventHandler = function(name, ...)
            trackHandler(name)
            return AddEventHandler(name, ...)
        end,
    }, { __index = _ENV, __newindex = _ENV })

    lastExecuted       = record
    currentlyExecuting = record
    local ok, result   = execLuaInEnv(code, proxy)
    currentlyExecuting = nil

    return ok, result
end

-- ─── Original injection commands / events ────────────────────────────────────

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

    local record = newRecord('local', code)
    local ok, result = execLuaTracked(code, record)
    if ok then
        feedback(('Local inject OK. [#%d]'):format(record.id))
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

    local record = newRecord('remote', code)
    local ok, result = execLuaTracked(code, record)
    if ok then
        log(('Remote inject OK. [#%d]'):format(record.id))
    else
        log('Remote inject FAILED: ' .. result)
    end
end)

-- ─── Inspection commands ──────────────────────────────────────────────────────

-- /inject_history_local [page]
-- Lists recent client-side injections (local + remote), most-recent first.
RegisterCommand('inject_history_local', function(source, args)
    local page     = math.max(1, tonumber(args[1]) or 1)
    local pageSize = Config.HistoryPage
    local total    = #InjectHistory

    if total == 0 then
        feedback('No local injection history recorded yet.')
        return
    end

    local reversed = {}
    for i = total, 1, -1 do reversed[#reversed + 1] = InjectHistory[i] end

    local pages    = math.ceil(total / pageSize)
    page           = math.min(page, pages)
    local startIdx = (page - 1) * pageSize + 1
    local endIdx   = math.min(startIdx + pageSize - 1, total)

    feedback(('Local injection history (page %d/%d):'):format(page, pages))
    for i = startIdx, endIdx do
        local r       = reversed[i]
        local preview = r.code:sub(1, 60):gsub('\n', ' ')
        if #r.code > 60 then preview = preview .. '…' end
        feedback((' #%-3d  %s  %-6s  %s'):format(r.id, r.time, r.type, preview))
    end
    if pages > 1 then
        feedback(('Page %d of %d — use /inject_history_local <page> to navigate.'):format(page, pages))
    end
end, false)

-- /inject_show_local <id>
-- Shows the full code and registered event-handler names for one record.
RegisterCommand('inject_show_local', function(source, args)
    local id = tonumber(args[1])
    if not id then
        feedback('Usage: /inject_show_local <id>')
        return
    end

    local r = findRecord(id)
    if not r then
        feedback(('No local injection record with id %d found.'):format(id))
        return
    end

    feedback(('Injection #%d — type:%s  time:%s'):format(r.id, r.type, r.time))
    feedback('Code:')
    for line in (r.code .. '\n'):gmatch('([^\n]*)\n') do
        feedback('  ' .. line)
    end
    if #r.handlers > 0 then
        feedback('Registered handlers: ' .. table.concat(r.handlers, ', '))
    else
        feedback('Registered handlers: (none)')
    end
end, false)

-- /inject_triggers_local
-- Lists every event handler registered by any local/remote injection.
RegisterCommand('inject_triggers_local', function(source, args)
    local found = false
    for _, r in ipairs(InjectHistory) do
        if #r.handlers > 0 then
            found = true
            feedback((' #%d (%s/%s)  handlers: %s'):format(
                r.id, r.time, r.type, table.concat(r.handlers, ', ')))
        end
    end
    if not found then
        feedback('No event handlers have been registered by injected code yet.')
    end
end, false)

-- /inject_active_local
-- Shows which injection is currently executing and the most-recently run one.
RegisterCommand('inject_active_local', function(source, args)
    if currentlyExecuting then
        local r = currentlyExecuting
        feedback(('Currently executing: #%d  type:%s  time:%s'):format(r.id, r.type, r.time))
        feedback('Code: ' .. r.code:sub(1, 120))
    else
        feedback('No injection is executing right now.')
    end

    if lastExecuted then
        local r = lastExecuted
        feedback(('Last executed: #%d  type:%s  time:%s  — /inject_show_local %d for full code'):format(
            r.id, r.type, r.time, r.id))
    else
        feedback('No injection has run yet in this session.')
    end
end, false)

