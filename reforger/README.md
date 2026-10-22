# AAR Recorder for Arma Reforger (prototype)

A script-only Reforger mod that records a mission on the server into the same `.jsonl` format as the Arma 3 recorder in [`extension/`](../extension/README.md). The viewer can then read recordings from both games. Reforger has no extension DLLs, so the whole recorder is Enforce Script. That also means BattlEye is no problem.

**Status:** prototype. It has not been compiled in Workbench or run yet. The script API calls were checked against the public 1.7 script API docs, but expect a round of compile fixes on first load.

## What it records

| type | notes |
|---|---|
| `header` | As in Arma 3, plus `game: "reforger"`, `world_file`, and `game_version` as a string. `mission`, `author`, `game_type` and `max_players` come from the scenario's mission header. `mission` may be a string table key such as `#AR-...`. |
| `entity` | Every character and vehicle. `class` is the prefab path, `display` is the prefab file name, and `side` is the faction key (`US`, `USSR`, `FIA`, ...). Units also carry `name`, `group`, `player`, `uid` (the BI identity id, not a Steam id) and `orbat`. |
| `snap` | Same layout and delta rules as Arma 3: `[id, x, y, z, dir, alive, damage, vehicle_id]`, every second, with a full keyframe every 60 s. |
| `killed` | `victim`, `killer`, `instigator`, `pos`, for AI and players alike. |
| `shot` | **Experimental.** `id`, `shooter`, `weapon` (prefab), `ammo` (projectile prefab when the engine passes one), and `pos`. It's here to find out whether player shots reach a dedicated server. There is no projectile flight or impact tracking yet. |
| `group` | `unit`, `group`, `side`, `orbat` when a unit's group changes. Checked on each keyframe. |
| `orbat` | `source: "reforger"`. One team per faction, built from the group callsigns as faction > company > platoon > squad. The node shape is the same as the TMF one. Units' `orbat` is their squad's node id, e.g. `US/Alpha/1/2`. Rewritten on a keyframe when the tree changes. |
| `player` | `unit`, `uid`, `name` when a player spawns into a unit. |
| `connected` / `disconnected` | `uid`, `name`, `owner` (the player id). |
| `deleted` | `id` |
| `idle` | Dedicated server only. Snapshots pause while no players are connected. |
| `end` | `reason` (`game_end` or `shutdown`), `entities` |

Positions: Enfusion vectors are `[x, up, z]`. The recorder writes `[x, z, up]`, so `x` is east, `y` is north and `z` is height, as in Arma 3. `dir` is the compass heading in degrees (0 = north, clockwise), computed from the entity's forward axis.

Not recorded yet: hits/damage events, vehicle get in/out, markers, perf.

## Where the file goes

`$profile:aar/YYYYMMDD-HHMMSS_<mission>_<world>.jsonl` (UTC). `$profile` is the profile folder: on a server, the one given with the `-profile` startup parameter (set it so you know where files land). For a local game it's under `Documents/My Games/ArmaReforger/profile/`. The console log shows `[AAR] recording to ...`.

## Trying it

1. In Arma Reforger Tools (Workbench), use **Add Existing** on `reforger/AARRecorder/addon.gproj` and open it.
2. Open any world, for example a Game Master scenario, and press Play. Fix any script compile errors Workbench reports, then play for a minute and stop.
3. Look in the profile folder for `aar/*.jsonl`.
4. For a dedicated server, publish the mod from Workbench (or pack it with **Pack Addon**) and add it to the server config's `mods`. Clients download it automatically, but only the server records.

## How it works

- `AAR_GameMode.c` adds a `modded class SCR_BaseGameMode`. On the server, `OnGameStart` creates the recorder and `OnGameEnd` closes it. Because it hooks the base game mode, every scenario is recorded without editing it.
- `AAR_Recorder.c` finds units and vehicles through the editable entity core, which holds every entity Game Master can see. It also tracks new ones through `Event_OnEntityRegistered` and the game mode's spawn event. Kills come from `GetOnControllableDestroyed`, and players from the game mode's player events. Shots come from the `OnProjectileShot` event on each entity's `EventHandlerManagerComponent`, the same hook the game's own stats collector uses on the server.
- A call queue tick runs every second. It builds the snapshot and appends the buffered lines to the open file.
- `AAR_Json.c` escapes strings and trims numbers.

## Open questions for the first test

- Does `OnProjectileShot` fire on a dedicated server for player-fired weapons? Watch for `shot` lines with a player as `shooter`.
- Are callsign string keys shaped like `#AR-..._Alpha`? If so, `Unlocalize` turns them into readable names. If not, group names will look odd.
- Does `GetPlayerIdentityId` return a value in Workbench? It's expected to be empty there and filled on a real server.
