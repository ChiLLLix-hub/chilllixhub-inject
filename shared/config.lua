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
