# chilllixhub-inject

A **FiveM resource** that provides a Lua code injector for development and testing purposes.  
It lets authorised players (and the server console) execute arbitrary Lua snippets on the server, on a specific client, or on all connected clients at once.

> ⚠️ **For testing / development environments only.**  
> Never run this resource on a public server — it can execute arbitrary code.

---

## Features

| Command | Side | Description |
|---|---|---|
| `/inject_server <code>` | Server | Execute Lua on the server |
| `/inject_client <id> <code>` | Server → Client | Execute Lua on a specific player's client |
| `/inject_all <code>` | Server → All clients | Execute Lua on every connected client |
| `/inject_file <path>` | Server | Load and execute a `.lua` file from inside the resource folder |
| `/inject_local <code>` | Client (local) | Execute Lua locally on your own client |

---

## Installation

1. Copy the `chilllixhub-inject` folder into your FiveM server's `resources` directory.
2. Add the following line to your `server.cfg`:

   ```
   ensure chilllixhub-inject
   ```

3. Grant the permission to the groups / players who should be allowed to use the injector:

   ```
   # Allow the built-in "admin" group
   add_ace group.admin chilllixhub.inject allow
   
   # Or allow a specific steam identifier
   add_ace identifier.steam:110000112345678 chilllixhub.inject allow
   ```

---

## Configuration

Edit `shared/config.lua` to change the defaults:

| Key | Default | Description |
|---|---|---|
| `Config.Permission` | `chilllixhub.inject` | ACE permission required to use commands |
| `Config.MaxCodeLength` | `8192` | Maximum characters per code snippet |
| `Config.ChatFeedback` | `true` | Show in-game chat feedback to the executor |
| `Config.LogPrefix` | `[chilllixhub-inject]` | Prefix used in all log / console output |

---

## Usage examples

```lua
-- Print all online player names to the server console
/inject_server for _, id in ipairs(GetPlayers()) do print(GetPlayerName(id)) end

-- Teleport player 3 to a position
/inject_client 3 SetEntityCoords(PlayerPedId(), 0.0, 0.0, 70.0, false, false, false, false)

-- Show a notification to every connected player
/inject_all SetNotificationTextEntry("STRING") AddTextComponentString("Hello from injector!") DrawNotification(false, true)

-- Execute a Lua file inside the resource folder (server-side)
/inject_file scripts/test_scenario.lua

-- Execute Lua on your own client (F8 console or in-game chat)
/inject_local print("My ped: " .. PlayerPedId())
```

---

## File structure

```
chilllixhub-inject/
├── fxmanifest.lua        – FiveM resource manifest
├── shared/
│   └── config.lua        – Shared configuration (loaded on server and clients)
├── server/
│   └── main.lua          – Server-side injector commands & logic
└── client/
    └── main.lua          – Client-side injector command & event handler
```

---

## License

MIT – use freely in your own testing environments.