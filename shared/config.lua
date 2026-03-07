-- chilllixhub-inject | shared/config.lua
-- Shared configuration loaded on both server and client.

Config = {}

-- ACE permission required to use injector commands.
-- Grant it with:  add_ace group.admin chilllixhub.inject allow
Config.Permission = 'chilllixhub.inject'

-- Maximum length (characters) of a single code snippet submitted via command.
-- Prevents accidental very large pastes from being processed.
Config.MaxCodeLength = 8192

-- Whether to print a chat message back to the executor on success / failure.
Config.ChatFeedback = true

-- Prefix shown in all console / log output.
Config.LogPrefix = '[chilllixhub-inject]'

-- Record event-handler registrations made by injected code so they can be
-- inspected with /inject_triggers and /inject_triggers_local.
Config.TrackTriggers = true

-- Maximum number of injection records kept in memory (server and client each).
Config.HistoryMax = 50

-- Number of entries shown per page in /inject_history and /inject_history_local.
Config.HistoryPage = 10

-- Enable the in-game NUI panel.
-- When true, the panel can be opened with the /inject_ui command or the
-- default key mapping (F6, re-bindable via FiveM key-binding settings).
Config.NUIEnabled = true
