# Arma AAR Recorder

Records an Arma 3 mission for After Action Review. An SQF addon collects unit and vehicle snapshots, kills, hits, every projectile from muzzle to impact, vehicle get in/out, player connects and markers, and hands the records in one batch per frame to a small extension (`arma_aar_x64.dll` / `.so`) that writes them to a `.jsonl` file on a background thread.

Open a recording in the [viewer](#viewing-a-recording) to play it back on a map and read everything in it.

## Installing

Every build on GitHub Actions uploads an `@arma_aar` artifact, the finished mod folder:

```
@arma_aar/
  addons/arma_aar_main.pbo
  arma_aar_x64.dll      (Windows)
  arma_aar_x64.so       (Linux server)
```

1. Start the server with it: `arma3server_x64.exe -serverMod=@arma_aar ...`. For a local test in the editor or singleplayer use `-mod=@arma_aar` on the game instead.
2. Play a mission. The RPT log shows `[AAR] recording to ...` and the file appears under `aar\` in the Arma folder.

Only the server records; clients do not need the mod. In singleplayer or a hosted game the host records.

**BattlEye:** with BattlEye on, Arma only loads extensions BattlEye has whitelisted, and this one is not. Run without BattlEye (no `-beservice`, or `BattlEye = 0;` in server.cfg) until it is. If the extension does not load, the RPT says `[AAR] arma_aar extension did not load`.

## Building

The extension is plain C++17 with no dependencies. Requires CMake 3.13+ and Visual Studio 2019/2022 (x64) on Windows, or GCC/Clang on Linux.

```
cmake -S . -B out -A x64              # Windows; on Linux: cmake -S . -B out -DCMAKE_BUILD_TYPE=Release
cmake --build out --config Release
python tools/pack_mod.py out build/Release/arma_aar_x64.dll
```

The GitHub Actions workflow in `.github/workflows/build.yml` does the same on every push and uploads the mod folder and the viewer page as artifacts.

`-DAAR_TESTS=ON` also builds `aar_tests`, which checks the record conversion. `hemtt check` lints the SQF and config.

## Output

Files go to `<Arma working directory>/aar/` by default, or to the folder in the `AAR_OUTPUT_DIR` environment variable. One file per mission, named `YYYYMMDD-HHMMSS_<mission>_<world>.jsonl` (UTC).

Every line is a JSON object with `type` and `t` (mission time in seconds, from `time`). Positions are `[x, y, z]` ASL in metres. Entities are referred to by a numeric id that is stable for the whole recording; `0` means "none or unknown".

| type | fields |
|---|---|
| `header` | `version`, `mission`, `world`, `started_utc`, `interval`, `keyframe_interval`, `multiplayer`. Mission metadata: `briefing_name`, `on_load_name`, `author`, `overview` (from description.ext), `game_type`, `max_players` (from its `Header` class), `server_name`, `world_name` (display name), `world_size` (m), `date` (in-game start `[year, month, day, hour, minute]`), `time_multiplier`, `weather` (`[overcast, fog, rain]` at start), `game_version` (`[version, build]`), `mods` (loaded non-official mod folders) |
| `entity` | first sighting of an entity: `id`, `kind` (`unit`, `car`, `tank`, `heli`, `plane`, `ship`, `static`, `vehicle`, `air`), `class`, `display`, `side`; units also have `name`, `group`, `player`, `uid`. With TMF: `orbat`, plus `loadout_faction`, `role`, `role_name` on units and `callsign`, `orbat_team` on vehicles (see "TMF" below) |
| `snap` | `key` (true for a full keyframe), `e`: array of `[id, x, y, z, dir, alive, damage, vehicle_id]` |
| `killed` | `victim`, `killer`, `instigator`, `pos` |
| `hit` | `unit`, `source`, `instigator`, `damage` Every recorded unit and vehicle, players included: see "Hits on players" below |
| `shot` | projectile created: `id` (projectile id), `shooter`, optional `parent` (for submunitions), optional `instigator` (the gunner when `shooter` is a vehicle), `weapon`, `ammo`, `pos`, `vel` |
| `submunition` | links a submunition (smoke or artillery shell, bomblet) recorded before its parent was known: `id`, `parent`, `shooter` |
| `proj_hit` | projectile directly hit a recorded unit or vehicle: `id`, `target`, `pos`, `part` (component hit, e.g. `head`); one line per component the projectile passes through, so consecutive lines trace penetration |
| `proj_splash` | explosive projectile damaged a recorded unit or vehicle: `id`, `target` |
| `proj_end` | projectile removed: `id`, `pos` (impact or end point), `exploded` |
| `get_in` / `get_out` | `vehicle`, `unit`, `role` (`driver`, `gunner`, `cargo`); `get_out` has `eject: true` for ejections |
| `seat` | `vehicle`, `unit`, `role`: a unit moved to another seat inside the vehicle |
| `group` | `unit`, `group`, `side` when a unit changes group or side; with TMF also `orbat` |
| `orbat` | TMF only, written once after the header: `source` (`tmf`), `teams`: one tree per side or faction, see "TMF" below |
| `loadout` | TMF only: `unit`, `loadout_faction`, `role`, `role_name` when TMF gives a unit its gear after it was first recorded |
| `player` | `unit`, `uid`, `name` when a player takes or leaves a unit (empty `uid` = now AI) |
| `respawn` | `new`, `old` |
| `connected` / `disconnected` | `uid`, `name`, `jip`, `owner` |
| `marker_created` / `marker_updated` / `marker_deleted` | `marker`, plus `text`, `markerType`, `color`, `channel`, `owner`, `pos` where available; `marker_deleted` has `by` (who deleted it) when known |
| `deleted` | `id` when an entity is removed from the world |
| `combat_mode` | an AI group's behaviour changed (`mode`: `SAFE`, `AWARE`, `COMBAT`, `STEALTH`, `CARELESS`), also written once when the group is first seen: `group`, `side`, `leader` |
| `enemy_detected` | an AI group detected a new enemy: `group`, `side`, `leader`, `target` |
| `fleeing` | an AI group started or stopped fleeing: `group`, `side`, `leader`, `fleeing` |
| `building` | a building or wall changed model, usually destroyed: `from`, `to` (classes), `ruin`, `pos` |
| `end` | `reason`, `entities` |
| `perf` | once per snapshot: server `fps`, `fps_min`, `units`, `entities`, `projectiles` in flight, and the recorder's own snapshot cost: `snap_frames` (frames it was spread over), `snap_ms` (total), `snap_max_ms` (worst frame), `batch` (entities per frame) |
| `idle` | `idle`: true when a dedicated server has no players left and snapshots stop, false when someone joins again |
| `perf_spike` | a server frame took longer than `spikeThreshold`: `frame_ms`, `recorder_ms` (the recorder's work in that frame), `fps`, `units`, `entities` |

Snapshots are deltas: an entity appears in a `snap` only when it moved more than 10 cm, turned more than 1°, or its alive/damage/vehicle state changed. Every `keyframe_interval` seconds a full snapshot (`"key":true`) lists every entity, so a player can seek to any keyframe and replay forward. Bodies and parked vehicles therefore cost nothing between keyframes.

Example:

```
{"type":"header","t":0,"version":1,"mission":"co40_assault","world":"Altis","started_utc":"2026-10-11T20:00:00Z","interval":1,"keyframe_interval":60,"multiplayer":true}
{"type":"entity","t":1,"id":1,"kind":"unit","class":"B_Soldier_F","display":"Rifleman","side":"WEST","name":"Sebastian","group":"Alpha 1-1","player":true,"uid":"7656119..."}
{"type":"snap","t":1,"key":true,"e":[[1,14520.4,16710.12,17.3,92,1,0,0]]}
{"type":"shot","t":34.52,"id":1,"shooter":1,"weapon":"arifle_MX_F","ammo":"B_65x39_Caseless","pos":[14530.1,16712.8,17.9],"vel":[880.2,-12.4,3.1]}
{"type":"proj_hit","t":34.62,"id":1,"target":7,"pos":[14610.2,16700.5,19.6],"part":"head"}
{"type":"proj_end","t":34.62,"id":1,"pos":[14610.2,16700.5,19.6],"exploded":false}
{"type":"killed","t":35.1,"victim":7,"killer":1,"instigator":1,"pos":[14610.2,16700.5,18.1]}
```

## Viewing a recording

Open the viewer on GitHub Pages (https://headswe.github.io/intercept-aar/, published from `main` by `.github/workflows/pages.yml`; `sample.html` there opens with a made-up recording), or open `viewer/aar-viewer.html` from the repository (a single file that needs no server; CI also uploads it as the `aar-viewer` artifact) and drop a `.jsonl` recording on it, or use **Open recording**. Nothing is uploaded anywhere; the file is read in the browser.

- **Map:** the mission plays back on a gridded map with Arma grid references: units and vehicles with facing, crew counts and players ringed, tracers from `shot` to `proj_end`, hit flashes, kill sites, map markers and destroyed buildings. Each group has a NATO-style marker over its living members with its name, size, AI behaviour (`SAFE`, `COMBAT`, ...) and whether it is fleeing; markers merge up the TMF ORBAT as you zoom out: once everything under a node fits in about 90 px, that node gets one marker (with a tick per group above it) instead of one per group. Groups outside the ORBAT merge with nearby groups of the same side. Markers that still overlap stack upwards. Recent events float as short labels over the unit or group they concern for a few seconds (behaviour changes, enemy spotted with a dashed line to the target, fleeing, vehicle seats, loadouts, respawns, kills). Detail follows the zoom: group markers while units crowd together (hidden once zoomed in close), per-unit event labels only once units are far enough apart to tell apart; `AWARE`, the AI default, is not labelled. Click a unit to see its status, TMF role and ORBAT position, and to follow it.
- **Link to a recording:** `?src=<url>` opens a recording from a web address, if that server allows cross-origin requests.
- **Map background:** MissionDB's R3-format tiles from `https://mission-db.1tac.eu/tiles/<slug>/tiles/{z}/{x}/{y}.png`, where the slug is the world name in lower case. The viewer first reads `tiles/config.json` (worlds that borrow another terrain's tiles) and `tiles/<slug>/config.json` (size, zoom range, background colour and `version`, which it adds to tile URLs as `?v=` so a re-tiled terrain is not served from cache). The layout follows Leaflet RasterCoords: one pixel per metre at the config's `maxZoom`, row 0 at the north edge, and zooms past it up to `dynamicMaxZoom` rendered on request. The tile host sends no CORS headers, so the page cannot read those files from another site. Instead the Pages build fetches them (`viewer/fetch_terrains.py`, for the worlds in `viewer/terrains.txt` plus every alias) and embeds them in the published page, and a daily run refreshes them. For a world that is not embedded, or in the downloadable `aar-viewer.html`, the viewer tries the live configs and otherwise uses `world_size` from the header (or a built-in size), computes the same native zoom, and uses a built-in copy of the alias list, which loses only the version and background colour. Add a world to `terrains.txt` to embed its config. Missing tiles fall back to a lower zoom. `?tiles=<base url>` points the viewer at another tile host.
- **Timeline:** shots per second as bars, kills as red ticks, server AI behaviour changes as small dark ticks, frame spikes as amber ticks and idle periods shaded. Click or drag to seek. Space plays and pauses, the arrow keys skip 5 s (30 s with Shift), and `[` / `]` change speed.
- **Events:** every event up to the current time, filterable by kind (kills, hits, vehicles, players, markers, AI, world, shots). Click one to jump to it.
- **Units:** the TMF ORBAT tree when the recording has one, with each node's units and who is still alive; otherwise units by side and group.
- **Mission:** everything in the header (mission, author, briefing, world, in-game date, weather, game version, mods), how the mission ended, and per-player stats.
- **Server:** server FPS, minimum FPS, units, entities and projectiles in flight over the mission from the `perf` records, the recorder's own cost, and a list of frame spikes.
- **Data:** a count of every record type in the file and the raw records of any type, so a field the viewer does not draw is still readable.

The page is generated from `viewer/viewer.body.html` by `viewer/build.py`; pass a recording to embed it as the example that opens with the page. `viewer/sample.py` writes a made-up recording that uses every record type, for trying the viewer out.

## Mission settings

Add this to a mission's `description.ext` to change the defaults (all optional).

```
class AAR {
    enabled = 1;            // 0 = do not record this mission
    interval = 1;           // seconds between snapshots
    keyframeInterval = 60;  // seconds between full snapshots
    logProjectiles = 1;     // shot / proj_hit / proj_splash / proj_end records
    logHits = 1;
    logMarkers = 1;
    frameBudget = 2;        // ms of recorder work per frame; snapshots are spread over frames to stay near it
    spikeThreshold = 100;   // ms; server frames slower than this get a perf_spike record and an RPT line
    pauseWhenEmpty = 1;     // dedicated server: no snapshots while no players are connected
    logAI = 1;              // combat_mode / enemy_detected / fleeing for AI groups
};
```

## How it works

- `fn_init.sqf` (postInit, server only) opens the file through the extension, writes the header and adds the mission event handlers, including `ProjectileCreated` with the projectile event handlers (`HitPart`, `HitExplosion`, `Explode`, `Deleted`, `SubmunitionCreated`).
- An `EachFrame` handler (`fn_frame.sqf`) starts a snapshot every `interval` seconds and works through it a batch of entities per frame (`fn_snapshot.sqf`), so a big mission spreads the work over several frames instead of one hitch. The extension times each of those frames, and the batch size adjusts to keep the recorder's work near `frameBudget` ms. The snap line is written once, stamped with the time the snapshot started. Everything queued in a frame goes to the extension in one `callExtension` call (`fn_flush.sqf`).
- Server frames slower than `spikeThreshold` are logged as `perf_spike` with the recorder's share, so a hitch can be told apart from one the recorder caused. The RPT gets `[AAR] frame spike: ...`.
- Records are built in SQF as JSON text, with strings written by `toJSON` and numbers by `toFixed`. The extension trims the numbers and appends the lines to the file from a background thread that flushes at least once a second.

Extension calls, for reference:

| call | does |
|---|---|
| `"arma_aar" callExtension ["open", [missionName, worldName]]` | closes any open file, opens a new one, returns `["<path>","<started utc>"]` |
| `"arma_aar" callExtension "tick"` | starts a timer |
| `"arma_aar" callExtension ["write", [records]]` | appends newline-separated records; returns microseconds since `tick` if one is pending |
| `"arma_aar" callExtension ["close", []]` | flushes and closes |
| `"arma_aar" callExtension "version"` | returns the version |

## TMF

When [TMF](https://github.com/TMF3/TMF) is loaded, the recording carries its ORBAT and loadouts, so a viewer can show the mission's chain of command instead of a flat list of groups.

- The `orbat` record holds the tree from the mission's ORBAT settings (`TMF_ORBATSettings`). Each entry in `teams` has `side` (`WEST`, `EAST`, `GUER`, `CIV`) or `faction`, and the root node. A node is `{"id", "name", "full_name", "icon", "modifier", "order", "children": [...]}`; `icon` and `modifier` are TMF texture paths.
- Units carry `orbat`, the node id their group was placed under (`TMF_OrbatParent`). Vehicles carry their own `orbat`, plus `callsign` and `orbat_team` when set in the editor. An entity without `orbat` belongs under its team's root node, as in TMF's own briefing.
- `role` and `loadout_faction` are TMF's assign gear classes (`r`, `sl`, ...), and `role_name` is the role's display name from `CfgLoadouts`. TMF gives players their gear on their own machine, so the role often arrives a moment later as a `loadout` record.

Without TMF none of these fields are written.

## Hits on players

A player's damage is decided on the player's own machine. The server's copy of the bullet usually agrees, but with lag it can hit or miss differently, so `proj_hit` on a player is the server's view of the shot. For the authoritative result the recorder uses `Hit` while an object is local to the server (AI) and switches to `MPHit` once it is not (players, headless client AI, vehicles they drive). `MPHit` is raised by the owner and broadcast, so `hit` reflects what the owner's machine applied. Its code runs on every machine, but it is one line that does nothing off the server, and clients need nothing installed. `killed` is always authoritative. MPHit does not fire for the killing blow.

## Lessons from other recorders

Before settling on this design we read OCAP2, R3 and Anrop's AAR addon. This one avoids what went wrong there:

- Strings go through `toJSON`, so names with quotes cannot break a record (R3, Anrop).
- Nothing is sent to clients and nothing a client sends is trusted; there is no admin event to spoof (OCAP).
- No scheduled script per projectile or per unit; everything runs in event handlers and one `EachFrame` handler (all three).
- Extension output is never `compile`d (R3), and the file is local, so there is no upload that can drop data or leak a token (Anrop, OCAP).
- Snapshots stop while a dedicated server is empty (R3, OCAP).
- New units and vehicles are registered by `EntityCreated` and removed by `EntityDeleted` the moment it happens, instead of scanning `allUnits` every second (R3, Anrop); a sweep on each keyframe is the safety net.

## Known limitations

- AI awareness records (`combat_mode`, `enemy_detected`, `fleeing`) come from group event handlers, which fire where the group is local. They cover AI the server runs, not groups on a headless client or led by a player. The wiki doesn't document this locality, so it is an assumption to check in-game.

- `logProjectiles` writes two or three lines per round. Large firefights produce big files and cost some server FPS in SQF; turn it off if you only need movement and kills.
- Bullet impacts on terrain and buildings are not logged as hits, only as the `proj_end` position.
- Needs Arma 3 2.18 or newer (`toJSON`, `ProjectileCreated` and the projectile event handlers).
- If a mission ends without `Ended` or `MPEnded` firing (for example leaving the editor preview), the file has no `end` line; the next mission closes it.
- Not tested in-game yet.
