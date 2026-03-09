-- chilllixhub-inject | client/main.lua
-- Client-side Lua injector.  For development / testing use only.
--
-- Commands (local, unrestricted – only affects the local player):
--   /inject_local            <lua code>  – execute a Lua snippet on this client
--   /inject_ui                           – toggle the NUI injector panel
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

-- ─── NUI panel ───────────────────────────────────────────────────────────────

if not Config.NUIEnabled then return end

local nuiOpen = false

--- Open or close the NUI injector panel.
local function setNuiVisible(visible)
    nuiOpen = visible
    SetNuiFocus(visible, visible)
    SendNUIMessage({
        action       = 'setVisible',
        visible      = visible,
        maxCodeLength = Config.MaxCodeLength,
    })
end

--- Send a list of history records to the NUI.
local function sendHistoryToNui()
    -- Build a JSON-serialisable copy (skip the metatable / function values).
    local data = {}
    for _, r in ipairs(InjectHistory) do
        data[#data + 1] = {
            id   = r.id,
            time = r.time,
            type = r.type,
            code = r.code,
        }
    end
    SendNUIMessage({ action = 'updateHistory', history = data })
end

-- /inject_ui  – toggle the NUI panel (also registered as a key mapping).
RegisterCommand('inject_ui', function()
    setNuiVisible(not nuiOpen)
end, false)

-- Default key mapping: F6 (user can rebind in FiveM key-binding settings).
RegisterKeyMapping('inject_ui', 'Toggle ChiLLLix Injector UI', 'keyboard', 'F6')

-- NUI → Lua: close button / Escape key.
RegisterNUICallback('close', function(_, cb)
    setNuiVisible(false)
    cb({})
end)

-- NUI → Lua: request current history.
RegisterNUICallback('getHistory', function(_, cb)
    local data = {}
    for _, r in ipairs(InjectHistory) do
        data[#data + 1] = {
            id   = r.id,
            time = r.time,
            type = r.type,
            code = r.code,
        }
    end
    cb({ history = data })
end)

-- NUI → Lua: execute code.
-- data.type    : 'local' | 'server' | 'client' | 'all'
-- data.code    : Lua source string
-- data.targetId: (integer, for type == 'client') target server-id
RegisterNUICallback('execute', function(data, cb)
    local code = data and data.code
    if type(code) ~= 'string' or #code == 0 then
        cb({ ok = false, msg = 'No code provided.' })
        return
    end
    if #code > Config.MaxCodeLength then
        cb({ ok = false, msg = ('Code too long (max %d chars).'):format(Config.MaxCodeLength) })
        return
    end

    local validTypes = { server = true, client = true, all = true }
    local injectType = validTypes[data.type] and data.type or 'local'

    if injectType == 'local' then
        -- Execute on this client immediately and return the result.
        local record = newRecord('local', code)
        local ok, result = execLuaTracked(code, record)
        sendHistoryToNui()
        if ok then
            cb({ ok = true,  msg = ('Local inject OK.'), id = record.id })
        else
            cb({ ok = false, msg = result })
        end
    else
        -- Ask the server to handle server / client / all injection.
        local targetId = (injectType == 'client') and tonumber(data.targetId) or nil
        TriggerServerEvent('chilllixhub-inject:nui_inject', injectType, code, targetId)
        cb({ ok = true, msg = ('Sent to server (target: %s).'):format(injectType) })
    end
end)

-- Receive execution feedback from the server for NUI-triggered injections.
AddEventHandler('chilllixhub-inject:nui_result', function(ok, msg, id)
    SendNUIMessage({ action = 'addResult', ok = ok, msg = msg, id = id })
end)

-- ─── Trigger Monitor ──────────────────────────────────────────────────────────

local monitorActive  = false
local monitorEntries = {}
local monitorNextId  = 1

--- Safely convert one value to a compact string for display in the monitor.
local function serializeValue(v)
    local t = type(v)
    if t == 'nil'     then return 'nil' end
    if t == 'boolean' then return tostring(v) end
    if t == 'number'  then return tostring(v) end
    if t == 'string'  then
        -- Escape quotes first, then truncate the escaped result so we never
        -- split an escape sequence at the boundary.
        local escaped = v:gsub('"', '\\"')
        if #escaped > 80 then escaped = escaped:sub(1, 80) .. '…' end
        return '"' .. escaped .. '"'
    end
    local ok, enc = pcall(json.encode, v)
    if ok and type(enc) == 'string' then
        return #enc > 120 and enc:sub(1, 120) .. '…' or enc
    end
    return tostring(v)
end

--- Build a comma-separated argument list string from variadic args.
local function serializeArgs(...)
    local parts = {}
    for i = 1, select('#', ...) do
        parts[i] = serializeValue(select(i, ...))
    end
    return table.concat(parts, ', ')
end

--- Append one entry to the in-memory log and push it to the NUI if open.
local function addMonitorEntry(direction, eventName, argsStr, srcInfo)
    local entry = {
        id    = monitorNextId,
        time  = os.date('%H:%M:%S'),
        dir   = direction,
        event = eventName,
        args  = argsStr or '',
        src   = srcInfo  or '',
    }
    monitorEntries[#monitorEntries + 1] = entry
    -- Trim the log to the configured maximum.
    while #monitorEntries > Config.MonitorMax do
        table.remove(monitorEntries, 1)
    end
    monitorNextId = monitorNextId + 1
    if nuiOpen then
        SendNUIMessage({ action = 'monitorEntry', entry = entry })
    end
end

-- ── Hook the global trigger functions ────────────────────────────────────────
-- We save the originals once and replace the globals with wrappers.
-- The wrappers are always installed; the `monitorActive` flag gates recording
-- so there is no measurable overhead when the monitor is off.

local _origTSE  = TriggerServerEvent
local _origTE   = TriggerEvent
local _origTLSE = TriggerLatentServerEvent

TriggerServerEvent = function(eventName, ...)
    if monitorActive and type(eventName) == 'string' then
        local ok, argsStr = pcall(serializeArgs, ...)
        addMonitorEntry('→ server', eventName, ok and argsStr or '?')
    end
    return _origTSE(eventName, ...)
end

TriggerEvent = function(eventName, ...)
    if monitorActive and type(eventName) == 'string' then
        local ok, argsStr = pcall(serializeArgs, ...)
        addMonitorEntry('↔ local', eventName, ok and argsStr or '?')
    end
    return _origTE(eventName, ...)
end

if _origTLSE then
    TriggerLatentServerEvent = function(eventName, bps, ...)
        if monitorActive and type(eventName) == 'string' then
            local ok, argsStr = pcall(serializeArgs, ...)
            addMonitorEntry('→ srv·latent', eventName, ok and argsStr or '?')
        end
        return _origTLSE(eventName, bps, ...)
    end
end

-- ── NUI callbacks ─────────────────────────────────────────────────────────────

RegisterNUICallback('startMonitor', function(_, cb)
    monitorActive = true
    -- Ask the server to start capturing events for us too.
    _origTSE('chilllixhub-inject:monitorStart')
    cb({ ok = true })
end)

RegisterNUICallback('stopMonitor', function(_, cb)
    monitorActive = false
    _origTSE('chilllixhub-inject:monitorStop')
    cb({ ok = true })
end)

RegisterNUICallback('clearMonitor', function(_, cb)
    monitorEntries = {}
    cb({ ok = true })
end)

RegisterNUICallback('getMonitorEntries', function(_, cb)
    cb({ entries = monitorEntries })
end)

-- Receive server-relayed event entries while the monitor is active.
AddEventHandler('chilllixhub-inject:monitorEvent', function(entry)
    if type(entry) ~= 'table' then return end
    entry.id  = monitorNextId
    if not entry.dir then entry.dir = '← srv·recv' end
    monitorEntries[#monitorEntries + 1] = entry
    while #monitorEntries > Config.MonitorMax do
        table.remove(monitorEntries, 1)
    end
    monitorNextId = monitorNextId + 1
    if nuiOpen then
        SendNUIMessage({ action = 'monitorEntry', entry = entry })
    end
end)

