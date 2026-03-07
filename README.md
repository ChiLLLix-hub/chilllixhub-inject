# chilllixhub-inject

A **FiveM resource** that provides a Lua code injector for development and testing purposes.  
It lets authorised players (and the server console) execute arbitrary Lua snippets on the server, on a specific client, or on all connected clients at once — either through a **built-in NUI panel** or the existing chat commands.

> ⚠️ **For testing / development environments only.**  
> Never run this resource on a public server — it can execute arbitrary code.

---

## Features

### NUI Injector Panel

Press **F6** (re-bindable in FiveM key-binding settings, or use `/inject_ui`) to open the in-game panel:

- **Code editor** – multi-line textarea with Tab support and character-count indicator
- **Target selector** – *Local*, *Server*, *Client* (with player-ID input), *All Clients*
- **Execute** with the **▶ Execute** button or **Ctrl + Enter**
- **Output log** – inline success / failure feedback for every injection
- **History sidebar** – shows recent injections; click any entry to load its code back into the editor
- **Close** with the **✕** button or **Escape**

### Injection commands

| Command | Side | Description |
|---|---|---|
| `/inject_ui` | Client | Toggle the NUI injector panel (also mapped to **F6**) |
| `/inject_server <code>` | Server | Execute Lua on the server |
| `/inject_client <id> <code>` | Server → Client | Execute Lua on a specific player's client |
| `/inject_all <code>` | Server → All clients | Execute Lua on every connected client |
| `/inject_file <path>` | Server | Load and execute a `.lua` file from inside the resource folder |
| `/inject_local <code>` | Client (local) | Execute Lua locally on your own client |

### Trigger inspection commands

These commands let you see **what was injected, what event handlers it registered, and which injection is currently running** – so you can quickly find and re-edit a specific trigger or function.

#### Server-side (require `Config.Permission` ACE)

| Command | Description |
|---|---|
| `/inject_history [page]` | List recent server-side injections (most-recent first). Shows ID, time, type, source, and a code preview. |
| `/inject_show <id>` | Display the full code and every event handler registered by injection `#id`. |
| `/inject_triggers` | List all event handlers registered via any injected code, grouped by injection. |
| `/inject_active` | Show which injection is currently executing, plus the last injection that ran. |

#### Client-side (local, no ACE check needed)

| Command | Description |
|---|---|
| `/inject_history_local [page]` | List recent local/remote injections received by this client. |
| `/inject_show_local <id>` | Display the full code and handlers for a local injection record. |
| `/inject_triggers_local` | List all event handlers registered by any local/remote injection. |
| `/inject_active_local` | Show which injection is currently executing on this client. |

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
| `Config.TrackTriggers` | `true` | Record `AddEventHandler`/`RegisterNetEvent` calls made by injected code |
| `Config.HistoryMax` | `50` | Maximum injection records kept in memory (per side) |
| `Config.HistoryPage` | `10` | Entries displayed per page in `*_history` commands |
| `Config.NUIEnabled` | `true` | Enable the in-game NUI panel (`/inject_ui` / F6) |

---

## Usage examples

### Using the NUI panel

1. Press **F6** (or type `/inject_ui`) to open the panel.
2. Select a **Target**: *Local*, *Server*, *Client*, or *All Clients*.
   - For *Client*, enter the player's server ID in the **Player ID** field.
3. Type or paste your Lua snippet in the code editor.
4. Press **▶ Execute** or **Ctrl + Enter**.
5. The **Output** area shows the result; the **History** sidebar lists all previous injections.
6. Click any history entry to reload that code into the editor.
7. Press **Escape** or the **✕** button to close the panel.

### Chat / console commands

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

### Trigger inspection workflow

```
-- 1. Inject code that registers an event handler
/inject_server AddEventHandler('myCustomEvent', function() print('fired!') end)
-- Output: Server inject OK. [#1]

-- 2. See all recent injections
/inject_history
-- Output: #1  14:02:05  server  src:console  AddEventHandler('myCustomEvent', ...

-- 3. View full code + registered handlers for injection #1
/inject_show 1
-- Output:
--   Injection #1 — type:server  time:14:02:05  src:console
--   Code:
--     AddEventHandler('myCustomEvent', function() print('fired!') end)
--   Registered handlers: myCustomEvent

-- 4. List all handlers from all injections at a glance
/inject_triggers
-- Output: #1 (14:02:05/server)  handlers: myCustomEvent

-- 5. Check what's actively running (useful inside async callbacks)
/inject_active
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
├── client/
│   └── main.lua          – Client-side injector command, event handler & NUI callbacks
└── html/
    ├── index.html        – NUI panel markup
    ├── style.css         – Dark-theme styles
    └── script.js         – NUI logic (execute, history, close, Lua ↔ NUI messaging)
```

---

## License

MIT – use freely in your own testing environments.