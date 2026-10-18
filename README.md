# Arma AAR Recorder

Records an Arma 3 mission for After Action Review. An SQF addon collects unit and vehicle snapshots, kills, hits, every projectile from muzzle to impact, vehicle get in/out, player connects, markers, chat on every channel and ACRE2 / TFAR radio traffic, and hands the records in one batch per frame to a small extension (`arma_aar_x64.dll` / `.so`) that writes them to a `.jsonl` file on a background thread.

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

Requires [CBA_A3](https://github.com/CBATeam/CBA_A3) on the server (TMF needs it anyway). Only the server records; clients do not need the mod. In singleplayer or a hosted game the host records.

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

The server `.rpt` log says where each recording went: look for `[AAR] recording to <path>`. If it says `Call extension 'arma_aar' could not be loaded` instead, nothing is recorded; on Linux check that `arma_aar_x64.so` sits next to `addons/` in the mod folder, and run `ldd arma_aar_x64.so` to see what it is missing. The CI build needs glibc 2.31 or newer (Ubuntu 20.04, Debian 11 or newer).

Every line is a JSON object with `type` and `t` (mission time in seconds, from `CBA_missionTime`). Events reported by clients (radio, markers, projectiles, hits, AI groups, chat, ACE) carry the client's `CBA_missionTime` from when they happened, which CBA keeps in step with the server, so they line up with the server's own records instead of landing when their batch arrived (a stamp more than 10 s old or in the future is held to that window). Positions are `[x, y, z]` ASL in metres. Entities are referred to by a numeric id that is stable for the whole recording; `0` means "none or unknown".

| type | fields |
|---|---|
| `header` | `version`, `mission`, `world`, `started_utc`, `interval`, `keyframe_interval`, `multiplayer`. Mission metadata: `briefing_name`, `on_load_name`, `author`, `overview` (from description.ext), `game_type`, `max_players` (from its `Header` class), `server_name`, `world_name` (display name), `world_size` (m), `date` (in-game start `[year, month, day, hour, minute]`), `time_multiplier`, `weather` (`[overcast, fog, rain]` at start), `game_version` (`[version, build]`), `mods` (loaded non-official mod folders) |
| `entity` | first sighting of an entity: `id`, `kind` (`unit`, `car`, `tank`, `heli`, `plane`, `ship`, `static`, `vehicle`, `air`), `class`, `display`, `side`, `faction` (class) and `faction_name`, `icon` (the class's map icon, a `CfgVehicleIcons` class such as `iconManMG`) and `icon_path` (its texture), `var_name` (editor variable name, when set); units also have `name`, `group`, `player`, `uid`, and `role_desc` (the slot description from the editor, e.g. `Rifleman@Alpha 1-1`) on playable units. With TMF: `orbat`, plus `group_short`, `group_icon`, `group_size`, `loadout_faction`, `loadout_faction_name`, `role`, `role_name` (and `radio_net`, `radio_channels` with TMF radio networks) on units and `callsign`, `orbat_team` on vehicles (see "TMF" below) |
| `snap` | `key` (true for a full keyframe), `e`: array of `[id, x, y, z, dir, alive, damage, vehicle_id]` |
| `killed` | `victim`, `killer`, `instigator`, `pos`, `credit` (`engine`, `ace` or `last_hit`, see "Kills and ACE medical" below), and when someone other than the victim is credited `weapon` and `weapon_name` (from the last hit by them) and `distance` (m, from where the shot was fired to where it hit, or between the two at death); `cause` with ACE medical (e.g. `#bleedout`) |
| `unconscious` / `awake` | a unit was knocked out (ACE medical, or vanilla incapacitated) or came to: `unit`, `pos`; `unconscious` has `by`, who last hit the unit in the 30 s before. Dying while unconscious writes `killed` only |
| `hit` | `unit`, `source`, `instigator`, `damage` Every recorded unit and vehicle, players included: see "Hits on players" below |
| `shot` | projectile created: `id` (projectile id), `shooter`, optional `parent` (for submunitions), optional `instigator` (the gunner when `shooter` is a vehicle), `weapon`, `ammo`, `pos`, `vel` |
| `submunition` | links a submunition (smoke or artillery shell, bomblet) recorded before its parent was known: `id`, `parent`, `shooter` |
| `proj_hit` | projectile directly hit a recorded unit or vehicle: `id`, `target`, `pos`, `part` (component hit, e.g. `head`); one line per component the projectile passes through, so consecutive lines trace penetration |
| `proj_splash` | explosive projectile damaged a recorded unit or vehicle: `id`, `target` |
| `proj_end` | projectile removed: `id`, `pos` (impact or end point), `exploded` |
| `get_in` / `get_out` | `vehicle`, `unit`, `role` (`driver`, `gunner`, `cargo`); `get_out` has `eject: true` for ejections |
| `seat` | `vehicle`, `unit`, `role`: a unit moved to another seat inside the vehicle |
| `group` | `unit`, `group`, `side` when a unit changes group or side; with TMF also `orbat`, `group_short`, `group_icon`, `group_size`, `radio_net`, `radio_channels` |
| `leader` | `unit`, `group`, `side` when a unit becomes its group's leader (checked each snapshot); the viewer puts the group's marker on it |
| `orbat` | TMF only, written once after the header: `source` (`tmf`), `teams`: one tree per side or faction, see "TMF" below |
| `radio_tx` | a player started transmitting (see "Radio" below): `unit`, `system` (`acre`, `tfar`), `radio_id`, `radio` (class), `radio_name`, `channel` (1-based), `freq` (MHz), optional `channel_name` (ACRE's channel label), `lr` (TFAR long range), `additional` (TFAR additional channel) |
| `radio_tx_end` | the transmission ended: `unit`, `system`, `radio_id` |
| `radios` | the radios a player carries, when that or a channel changes: `unit`, `system`, `radios` (list of `{radio_id, radio, radio_name, channel, freq, channel_name}`) |
| `radio_nets` | TMF only, once near the start: `source` (`tmf`), `nets`, see "Radio" below |
| `loadout` | TMF only: `unit`, `loadout_faction`, `loadout_faction_name`, `role`, `role_name` when TMF gives a unit its gear after it was first recorded |
| `player` | `unit`, `uid`, `name` when a player takes or leaves a unit (empty `uid` = now AI) |
| `respawn` | `new`, `old` |
| `connected` / `disconnected` | `uid`, `name`, `jip`, `owner` |
| `marker_created` / `marker_updated` / `marker_deleted` | `marker` (name), and on created / updated the whole state: `text`, `markerType`, `color`, `shape` (`ICON`, `RECTANGLE`, `ELLIPSE`, `POLYLINE`), `brush`, `size` (`[a, b]`, half-sizes in metres for areas), `dir`, `alpha`, `pos`, `line` (polylines: `[x1, y1, x2, y2, ...]`); created also has `channel` and `owner`, or `editor: true` for markers already on the map when the recording started; `marker_deleted` has `by` (who deleted it) when known. Markers created, moved or deleted by server scripts are recorded like player-drawn ones; the Cover Map module's shading markers are left out (recorded as `cover_map`). Player markers on channels other than Global (side, command, group, vehicle, direct) never reach the server, so each client reports its own, the same way as radio traffic |
| `chat` | a chat message: `channel` (0 global, 1 side, 2 command, 3 group, 4 vehicle, 5 direct, 6-15 custom, 16 system), `text`, and when known `channel_name` (custom channels), `unit` (sender), `name` (sender's name), `from` (the sender as the chat shows it, when it differs from `name`), `player: true` for messages a player typed. Who it went to: `to_side` on side and command messages, `to_group` and `to_side` on group messages, `to_vehicle` (id) on vehicle messages, taken from the sender's unit when it was sent. Chat on most channels never reaches a dedicated server, so each player reports the messages they type, the same way as markers; the server records the rest it sees itself (system messages, chat from server scripts). Lines starting with `#` (server commands such as `#login`) are never recorded |
| `cover_map` | a Cover Map module's uncovered area, at the start and whenever it moves or changes: `id`, `pos`, `area` (`[a, b, angle]` like `triggerArea`), or `removed: true` once the module is gone |
| `deleted` | `id` when an entity is removed from the world |
| `combat_mode` | an AI group's behaviour changed (`mode`: `SAFE`, `AWARE`, `COMBAT`, `STEALTH`, `CARELESS`), also written once when the group is first seen: `group`, `side`, `leader` |
| `enemy_detected` | an AI group detected a new enemy: `group`, `side`, `leader`, `target`. The same group and target are logged at most once per `enemyDetectedCooldown` seconds (default 120). |
| `fleeing` | an AI group started or stopped fleeing: `group`, `side`, `leader`, `fleeing` |
| `wound` | ACE medical: a unit was wounded: `unit`, `wounds` (`[[body part, damage], ...]`, body parts as ACE names them: `Head`, `Body`, `LeftArm`, `RightArm`, `LeftLeg`, `RightLeg`), `cause` (the ammo class, or ACE's cause such as `burn`, `drowning`, `vehiclecrash`), `by` (who caused it, when known), `pos` |
| `treatment` | ACE medical: a medic's treatment `result` (`started`, `done`, `failed` when interrupted): `medic`, `patient`, `part` (body part, lower case), `action` (ACE treatment class, e.g. `FieldDressing`, `Morphine`, `CPR`), `item` (the item used, when one was) |
| `drag` | ACE: a unit started or stopped dragging or carrying another unit or object: `unit`, `target`, `how` (`drag`, `carry`), `started`, `pos` |
| `team` | ACE: a unit was assigned a fireteam colour through ACE's interaction menu: `unit`, `team` (`MAIN`, `RED`, `GREEN`, `BLUE`, `YELLOW`) |
| `captive` | ACE: a unit was handcuffed, surrendered, or released: `unit`, `captive`, `reason` (`SetHandcuffed`, `SetSurrendered`), `by` (who did it, when known), `pos` |
| `explosive` | ACE explosives: `action` (`placed` when set down, `armed` when its trigger is set, `defusing`, `defused`, `defuse_exploded`), `class` (the magazine for `placed`, otherwise the explosive's class), `explosive` (a number per armed explosive, to follow it from `armed` to its defusal), `by`, `pos`. A defused or blown up explosive is often gone by the time the server hears of it; its record then has the unit's position and no `class` or `explosive` |
| `tripflare` | ACE trip flare set off: `pos` |
| `building` | a building or wall changed model, usually destroyed: `from`, `to` (classes), `ruin`, `pos` |
| `end` | `reason`, `entities` |
| `perf` | once per snapshot: server `fps`, `fps_min`, `units`, `entities`, `projectiles` in flight, and the recorder's own snapshot cost: `snap_frames` (frames it was spread over), `snap_ms` (total), `snap_max_ms` (worst frame), `batch` (entities per frame) |
| `idle` | `idle`: true when a dedicated server has no players left and snapshots stop, false when someone joins again |
| `perf_spike` | a server frame took longer than `spikeThreshold`: `frame_ms`, `recorder_ms` (the recorder's frame handler in that frame: snapshot and writing, not its event handlers), `fps`, `units`, `players`, `entities`, `projectiles` (in flight) |

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

Open the viewer on GitHub Pages (https://headswe.github.io/intercept-aar/, published from `main` by `.github/workflows/pages.yml`; `sample.html` there opens with a made-up recording on Stratis, and **Sample data** loads the same one), or open `viewer/aar-viewer.html` from the repository (a single file that needs no server; CI also uploads it as the `aar-viewer` artifact) and drop a `.jsonl` recording on it, or use **Open recording**. Nothing is uploaded anywhere; the file is read in the browser.

Served from a web server, the viewer also looks for an `aar/` folder next to the page and lists the `.jsonl` recordings in it under **Recordings**, newest first. It reads `aar/index.json` if there is one (a JSON list of file names, or of `{"name", "size", "modified"}`), otherwise the server's directory listing (nginx `autoindex on`, Apache `Options +Indexes`, `python3 -m http.server`). So putting `aar-viewer.html` next to the server's `aar` folder and serving that directory is enough. A page opened straight from disk can't list folders, so the button stays hidden there.

- **Map:** the mission plays back on a gridded map with Arma grid references: units and vehicles with facing, crew counts and players ringed, tracers from `shot` to `proj_end`, hit flashes, kill sites, map markers (icons, areas with their brush, lines drawn on the map) and destroyed buildings; with a Cover Map module everything outside its area is shaded, as in game. Each group has a TMF-style marker on its leader: its TMF group marker icon, size and text, with the same symbols and squad colours as TMF's ORBAT tracker (groups without one get their ORBAT node's icon, or a plain marker in their side's colour, and their group name). Markers merge up the TMF ORBAT by TMF's own rules: a node sits at the mean of its groups and sub-nodes, and once its furthest group is within about 54 px of it on screen (0.05 Arma screen units) the node's marker replaces theirs; nodes without an icon never merge. A marker's text is hidden while a sibling sits within about 40 px. Markers keep one size at every zoom and fade when zoomed in close. Groups outside the ORBAT merge with nearby groups of the same side by the same distance. Hover a marker for the group's name, AI behaviour (`SAFE`, `COMBAT`, ...), whether it is fleeing and its players; hover a unit for its name. Unconscious units are drawn faded with a dashed ring and no facing; zoomed in, a unit's dot carries a letter for its class's map icon (`L` leader, `O` officer, `M` machine gunner, `A` AT, `+` medic, `E` engineer, `X` explosives, `R` recon). Recent events float as short labels over the unit or group they concern for a few seconds (behaviour changes, enemy spotted with a dashed line to the target, fleeing, vehicle seats, loadouts, respawns, kills). Per-unit event labels show only once units are far enough apart to tell apart; `AWARE`, the AI default, is not labelled. Click a unit to see its status (including unconscious), faction, slot description, variable name, TMF role and ORBAT position, its shots and kills so far (with `+N` for those in the last 10 seconds), and to follow it. Kills in the event feed show the weapon and distance.
- **Link to a recording:** `?src=<url>` opens a recording from a web address, if that server allows cross-origin requests. `?recording=<id>` opens one from the **Recordings** list (a file name in the `aar/` folder, or an id from the [recordings API](#recordings-from-an-api)); picking a recording puts it in the address bar, so the link can be shared.
- **Share a moment or a clip:** **Share** next to the clock copies a link to the current time (`&t=<seconds>`) or to a clip (`&t=` and `&end=`; set its start and end with **Now** or by typing `m:ss`), optionally following the selected unit (`&unit=<id>`). A clip link starts playing at the clip's start, stops at its end, and shades the rest of the timeline; the **Clip** button beside **Share** clears it. Times can also be written `12:34`, `1:02:03` or `12m34s`. A recording opened from a file has no link, so only the time can be shared then. `apiHeaders` is never copied into a shared link.
- **Map background:** MissionDB's R3-format tiles from `https://mission-db.1tac.eu/tiles/<slug>/tiles/{z}/{x}/{y}.png`, where the slug is the world name in lower case. The viewer first reads `tiles/config.json` (worlds that borrow another terrain's tiles) and `tiles/<slug>/config.json` (size, zoom range, background colour and `version`, which it adds to tile URLs as `?v=` so a re-tiled terrain is not served from cache). The layout follows Leaflet RasterCoords: one pixel per metre at the config's `maxZoom`, row 0 at the north edge, and zooms past it up to `dynamicMaxZoom` rendered on request. The tile host sends no CORS headers, so the page cannot read those files from another site. Instead the Pages build fetches them (`viewer/fetch_terrains.py`, for the worlds in `viewer/terrains.txt`, taken from MissionDB's terrain list, plus every alias) and embeds them in the published page, and a daily run refreshes them. MissionDB sometimes answers 502, so the build retries, keeps any config it still cannot fetch from the published page, and fails rather than replace a page that has configs with one that has none. For a world that is not embedded, or in the downloadable `aar-viewer.html`, the viewer tries the live configs and otherwise uses `world_size` from the header (or a built-in size), computes the same native zoom, and uses a built-in copy of the alias list, which loses only the version and background colour. Add a world to `terrains.txt` to embed its config. Missing tiles fall back to a lower zoom. To use another tile service, see [Your own tiles, names and icons](#your-own-tiles-names-icons-and-look).
- **Timeline:** shots per second as bars, kills as red ticks, server AI behaviour changes as small dark ticks, frame spikes as amber ticks and idle periods shaded. Click or drag to seek. Space plays and pauses, the arrow keys skip 5 s (30 s with Shift), and `[` / `]` change speed.
- **Events:** every event up to the current time, filterable by kind (kills, hits, medical, vehicles, players, markers, AI, world, shots); medical covers ACE wounds, treatment and dragging or carrying. Click one to jump to it.
- **Radio:** transmissions on the map as waves around the speaker with the channel name, a teal bar per transmission on the timeline, and a Radio tab with TMF's networks and channels (frequency, how many transmissions, time on air, units assigned), other channels heard, who talked most, and every transmission (click one to jump to it). A transmission takes its name from the TMF channel on the same frequency, else ACRE's channel label, else the channel number. A unit's card lists its radios, its TMF network and channels, and what it is transmitting on.
- **Chat:** every message in the event feed with its channel, a pink tick per message on the timeline, what a unit typed shown next to it on the map for a few seconds, and a Chat tab listing all messages with a checkbox per channel (click one to jump to it).
- **Units:** the TMF ORBAT tree when the recording has one, with each node's units and who is still alive; otherwise units by side and group.
- **Mission:** everything in the header (mission, author, briefing, world, in-game date, weather, game version, mods), how the mission ended, and per-player stats (with ACE, the treatments each player gave others).
- **Server:** server FPS, minimum FPS, units, entities and projectiles in flight over the mission from the `perf` records, the recorder's own cost, and a list of frame spikes.
- **Data:** a count of every record type in the file and the raw records of any type, so a field the viewer does not draw is still readable.

### Names and icons from the game

Recordings keep class names only. The viewer gets display names and the game's textures from files next to the recordings, which the server writes when you ask it to. Run this on the server after changing mods, for example from the debug console as a logged-in admin with **Server Exec**:

```sqf
[] spawn aar_fnc_gameData
```

The recorder reads the names from the config and hands them to the extension, which writes on a background thread:

- `aar-cfg.json`: display names, pictures and map icon classes for every vehicle and unit class, weapon names and pictures, faction names and flags, the `CfgVehicleIcons` and `CfgMarkers` tables, and each marker's resolved default color and `showEditorMarkerColor` setting.
- `icons/<texture path>.png`: every map icon, vanilla marker icon, vehicle and weapon picture and faction flag, found in the PBOs of the game and the loaded mods and converted from `.paa`, which browsers cannot read.
- `aar-icons.json`: the list of those PNGs by texture path.

When it is done it logs `[AAR] game data export: ... PNGs written ...` to the RPT. Serve the `aar` folder with the viewer and it uses all of it.

The same files can be made by hand on a PC with the game, for a viewer that is not served from the server (the hand-made `aar-icons.json` holds the PNGs itself, so it also works when opened from disk):

1. **Names:** start the editor with the server's mods, open the debug console (Tools > Debug Console), paste `tools/export_cfg.sqf`, press **Local Exec**, and paste the clipboard into a file named `aar-cfg.json`.
2. **Icons and pictures:** `python3 tools/export_icons.py "C:/Program Files (x86)/Steam/steamapps/common/Arma 3" -c aar-cfg.json -r path/to/aar` (Python 3, no packages). It searches the folders given (Arma's own folder covers the DLCs and `!Workshop`; add other mod folders after it) and exports every map and vanilla marker icon in `aar-cfg.json`, the pictures of the vehicles and weapons the given recordings use (every picture with `--all-pictures`, which makes a large file) and any other `.paa` a recording names, such as TMF group and ORBAT icons. `--include <path>` adds every texture under a path inside the PBOs. Running it again merges into the existing file. Open a hand-made file in the viewer rather than putting it in the server's `aar/` folder, where the next export replaces it.

Served over http, the viewer picks up `aar-cfg.json` and `aar-icons.json` from next to the page or from `aar/`. Files can also be opened in the viewer (with **Open recording** or by dropping them, together with a recording or on their own); it keeps them in the browser for next time, and icons from several files add up. With them, weapons in the event feed show their names, zoomed-in units and vehicles are drawn with the game's map icon in their side's colour, and a vehicle's card shows its picture. Without them the viewer works as before.

### Your own tiles, names, icons and look

The viewer's sources and look are set in one place, so it can be pointed at your own tile service, name data, icons and recordings, and carry your own logo and colours. Put a `viewer-config.json` next to the page (or name another file with `?config=<url>`). Every key is optional; what is left out keeps the default shown here:

```json
{
  "tiles": "https://mission-db.1tac.eu/tiles/",
  "tileUrl": "{tiles}{slug}/tiles/{z}/{x}/{y}.png",
  "terrainConfig": "{tiles}{slug}/config.json",
  "terrainAliases": "{tiles}config.json",
  "aliases": {},
  "terrains": {},
  "cfg": ["aar-cfg.json", "aar/aar-cfg.json"],
  "icons": ["aar-icons.json", "aar/aar-icons.json"],
  "iconUrl": "",
  "recordings": "aar/",
  "recordingsApi": "",
  "recordingUrl": "",
  "apiHeaders": {},
  "apiCredentials": "",
  "title": "AAR Viewer",
  "logo": "",
  "logoLink": "",
  "css": [],
  "theme": {}
}
```

- `tiles`: the tile service's base URL, which the templates below use as `{tiles}`.
- `tileUrl`: where a tile is. `{slug}` is the terrain's tile folder (the world name in lower case unless an alias says otherwise), `{world}` the world name, `{z}/{x}/{y}` the tile, with row 0 at the terrain's north edge and one pixel per metre at the terrain's `maxZoom` (Leaflet RasterCoords, as MissionDB and R3 tile). The terrain's `version` is added as `?v=` unless the template has `{v}`.
- `terrainConfig`: a terrain's size and zoom range, in MissionDB's format: `width`, `height`, `minZoom`, `maxZoom`, `dynamicMaxZoom`, `doubleSize`, `bgColor`, `version` (all optional). `""` skips it and sizes the map from the recording's `world_size`.
- `terrainAliases`: a JSON object mapping worlds to the slug of the terrain whose tiles they use. `""` skips it.
- `aliases` and `terrains`: the same, written into the config itself, used before anything is fetched. This is how to use a tile host that sends no CORS headers, since the page cannot read JSON from such a host, only images. The built-in alias table (winter maps to their summer tiles) still applies under `aliases`. MissionDB's copies embedded in the published page are only used while the tile settings are MissionDB's.
- `cfg` and `icons`: where `aar-cfg.json` (names) and `aar-icons.json` (texture list) are; for each, the first one that loads is used. PNG paths in an icon list are relative to the list. The formats are those of [Names and icons from the game](#names-and-icons-from-the-game): `aar-cfg.json` is `{"format":"aar-cfg","vehicles":{"<class>":["<name>","<picture>","<map icon class>","<faction>"]},"weapons":{"<class>":["<name>","<picture>"]},"factions":{"<class>":["<name>","<flag>"]},"vehicle_icons":{"<CfgVehicleIcons class>":"<texture>"}}` on one line, and `aar-icons.json` is `{"format":"aar-icons","icons":{"<texture path>":"<png url or data: URI>"}}`, with texture paths in lower case with backslashes and `.paa`.
- `iconUrl`: where to find a texture the icon list does not have, or every texture when there is no list. A base URL like `https://example.com/icons/` takes the extension's layout (`<base>a3/ui_f/data/map/vehicleicons/iconman_ca.png` for `a3\ui_f\data\map\vehicleicons\iconman_ca.paa`); a template takes `{path}` (that path, without the extension) or `{key}` (the game's path, URL-encoded).
- `recordings`: the folder listed under **Recordings**, read through its `index.json` or the server's directory listing. `""` turns the list off.
- `recordingsApi`, `recordingUrl`, `apiHeaders`, `apiCredentials`: list and fetch recordings from an API instead of a folder; see [Recordings from an API](#recordings-from-an-api).
- `title`: the name in the header and the browser tab.
- `logo` and `logoLink`: an image shown before the title (28 px high), and where clicking it goes.
- `css`: extra stylesheets loaded after the page's own, for web fonts or any other styling.
- `theme`: the page's colour and font variables (the CSS variables at the top of `viewer/viewer.body.html`, without `--`): `ground` (map paper), `panel`, `ink`, `ink-soft`, `rule`, `grid`, `grid-major`, `accent` (selection, playhead, tracers), `west`, `east`, `guer`, `civ` (side colours), `dead`, `radio`, `chat`, `font-display`, `font-ui`, `font-data`. Keys at the top apply in both light and dark mode, `light` and `dark` hold values for one mode, and `mode` (`"light"` or `"dark"`) fixes the mode instead of following the system setting. The map, timeline and charts use the same colours. For example:

  ```json
  "theme": { "accent": "#7a1fa2", "font-display": "Oswald, sans-serif",
             "light": { "ground": "#f3efe6" }, "dark": { "ground": "#101418" } }
  ```

Relative URLs are relative to the page. Each key can also be given as a URL parameter, which wins over the file, for example `?tiles=https://tiles.example.com/&cfg=https://data.example.com/aar-cfg.json` (`aliases`, `terrains` and `theme` as JSON). Files on another site need that site to allow cross-origin requests (map tiles and icons excepted; a vehicle card shows its picture from another site only when that site allows it). A page opened from disk cannot read a `viewer-config.json` next to it, so `python3 viewer/build.py --config viewer-config.json` builds an `aar-viewer.html` with the config inside it. A broken config is reported above the map.

#### Recordings from an API

When recordings live behind an application (a database, object storage, a login) rather than in a folder, set `recordingsApi` to a list endpoint and the **Recordings** button lists from it instead of the folder:

```json
{
  "recordingsApi": "https://aar.example.com/api/recordings",
  "recordingUrl": "{api}/{id}",
  "apiHeaders": { "Authorization": "Bearer <token>" },
  "apiCredentials": "include"
}
```

The viewer sends `GET <recordingsApi>` and expects JSON, either a plain array of entries or an object with the entries and paging:

```json
{
  "recordings": [
    { "id": "20261017-191500_co12_raid_Stratis", "title": "CO12 Village Raid", "world": "Stratis",
      "date": "2026-10-17T19:15:00Z", "duration": 3540, "size": 18233344,
      "name": "20261017-191500_co12_raid_Stratis.jsonl", "url": "/files/abc123.jsonl" }
  ],
  "next": "/api/recordings?cursor=abc",
  "total": 214
}
```

- `id` (required): any string or number, unique per recording. It is what `?recording=<id>` takes.
- `title`, `world`, `date` (ISO 8601), `duration` (seconds), `size` (bytes): shown in the list, all optional. Without a `title` the list falls back to the mission and world in a recorder file `name`, then to the `name` or `id` itself.
- `url` (optional): where to fetch this recording. Without one the viewer fills `recordingUrl` with `{api}` (`recordingsApi` without its query string) and `{id}` (URL-encoded); the default is `{api}/{id}`.
- `recordings` may also be called `items`. List the newest first; the viewer keeps the order.
- `next` (optional): the URL of the next page, absolute or relative to the list URL (cursor, offset or page number, whatever the API uses). While there is one, the list ends with **Load more**. `total` (optional) shows as "Recordings (50 of 214)".

A recording URL returns the `.jsonl` text as the recorder wrote it (any content type; gzip it with `Content-Encoding: gzip` to save bandwidth, browsers unpack it). Both kinds of request carry `apiHeaders` and use `apiCredentials` as the fetch `credentials` mode (`"include"` sends the API's cookies to another site, `"omit"` none; the default sends them only to the page's own site). An API on another site must answer CORS: `Access-Control-Allow-Origin` with the viewer's origin, and for headers or cookies the matching `OPTIONS` preflight (`Access-Control-Allow-Headers: Authorization`, `Access-Control-Allow-Credentials: true`). Anything in `apiHeaders` is readable by whoever can load the config, so a bearer token there only suits a private viewer; for a viewer anyone can open, put the API behind a login and use cookies with `apiCredentials`. `?recording=<id>` fetches the recording directly without waiting for the list. An API error is reported above the map.

`tools/aar_api_server.py` is a reference implementation in plain Python 3: it serves a server's `aar` folder as `GET /api/recordings?limit=&offset=` (title, world and date from each file's header line, duration from its last records) and `GET /api/recordings/<file name>`, with an optional bearer token and CORS origin, and with `--viewer` it serves the viewer at `/` already pointed at the API:

```sh
python3 tools/aar_api_server.py /home/arma/arma3/server/aar --viewer viewer/aar-viewer.html --bind 0.0.0.0 --port 8080
```

It is a reference for the contract rather than a hardened server; put it behind a real web server with TLS before exposing it to the internet.

The page is generated from `viewer/viewer.body.html` by `viewer/build.py`; pass a recording to embed it as the example that opens with the page. `viewer/sample.py` writes a made-up recording that uses every record type, for trying the viewer out.

## Settings

The recorder's options are CBA settings, under **AAR** in Options > Addon Options (Recording, Events, Performance). They are server settings: set them for every mission in the server's `userconfig\cba_settings.sqf` (or from the in-game menu as a logged-in admin with the mod loaded), or for one mission in the Eden editor's Addon Options, which CBA saves in the mission. They are read when the mission starts, so a change applies to the next mission. Each one is the variable `aar_setting_<key>`, for example:

```
force aar_setting_enemyDetectedCooldown = 60;
aar_setting_logChat = false;
```

A mission can also override any setting in its `description.ext` (all optional). A key here wins over the CBA setting.

```
class AAR {
    enabled = 1;            // 0 = do not record this mission
    interval = 1;           // seconds between snapshots
    keyframeInterval = 60;  // seconds between full snapshots
    logProjectiles = 1;     // shot / proj_hit / proj_splash / proj_end records
    logHits = 1;
    logMarkers = 1;         // map markers, from the editor and placed or drawn by players
    frameBudget = 2;        // ms of recorder work per frame; snapshots are spread over frames to stay near it
    spikeThreshold = 100;   // ms; server frames slower than this get a perf_spike record and an RPT line
    pauseWhenEmpty = 1;     // dedicated server: no snapshots while no players are connected
    logAI = 1;              // combat_mode / enemy_detected / fleeing for AI groups, on the server, headless clients and player-led groups
    enemyDetectedCooldown = 120; // seconds before a group re-detecting the same target is logged again; 0 = every time
    logRadio = 1;           // radio_tx / radios / radio_nets with ACRE2 or TFAR
    logChat = 1;            // chat records: what players type on every channel, plus system and script messages the server sees
    logACE = 1;             // with ACE: wound / treatment / drag / team / captive / explosive / tripflare records
};
```

## How it works

- `fn_init.sqf` (postInit, server only) opens the file through the extension, writes the header and adds the mission event handlers, including `ProjectileCreated` with the projectile event handlers (`HitPart`, `HitExplosion`, `Explode`, `Deleted`, `SubmunitionCreated`).
- Only the firing machine's copy of a projectile hits, explodes and ends reliably; the server's copy of a player's bullet never reports a hit. So the server records the projectiles its own units fire, and sends every other machine (players and headless clients) `fn_projectileClient.sqf`, which records the projectiles fired by that machine's units and sends them to `aar_fnc_projectileReport` four times a second, with how long ago each event happened so the server stamps the right time. A mission with its own `CfgRemoteExec` in whitelist mode needs `class aar_fnc_projectileReport { allowedTargets = 2; };` (and the same for `aar_fnc_hitReport`). The server's own copies of other machines' submunitions (artillery and smoke shells, bomblets) are held until a parent the server recorded claims them, so they are not written twice.
- An `EachFrame` handler (`fn_frame.sqf`) starts a snapshot every `interval` seconds and works through it a batch of entities per frame (`fn_snapshot.sqf`), so a big mission spreads the work over several frames instead of one hitch. The extension times each of those frames, and the batch size adjusts to keep the recorder's work near `frameBudget` ms. The snap line is written once, stamped with the time the snapshot started. Everything queued in a frame goes to the extension in one `callExtension` call (`fn_flush.sqf`).
- Server frames slower than `spikeThreshold` are logged as `perf_spike` with the recorder's share, so a hitch can be told apart from one the recorder caused. A spike with `recorder_ms` near 0 came from something else on the server (mission scripts, AI, a player joining). The RPT gets `[AAR] frame spike: ...`.
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
- ORBAT team headings use the unique TMF loadout faction display name when there is one; when several are present, the heading shows the team's side (`BLUFOR`, `OPFOR`, `INDEPENDENT` or `CIVILIAN`) followed by the names. Faction-keyed teams without loadout names fall back to their Arma faction display name.
- `role` and `loadout_faction` are TMF's assign gear classes (`r`, `sl`, ...); `role_name` and `loadout_faction_name` are their `displayName` values from `CfgLoadouts`. In the viewer's unit card, the loadout faction name is shown as the faction when available; otherwise it falls back to the Arma faction name. The viewer tracks loadout records over time, so seeking shows the role and faction assigned at that point. TMF gives players their gear on their own machine, so the role often arrives a moment later as a `loadout` record. These identify the assigned role and faction, not the unit's individual inventory.

Without TMF none of these fields are written.

## Player markers

The server only receives markers drawn on the Global channel; markers on the side, command, group, vehicle or direct channel stay with the players on that channel. So the server also sends every machine with a player a small piece of code (`fn_markerClient.sqf`, via `remoteExecCall` and queued for players who join later; nothing to install on clients). The player who places, moves or deletes such a marker reports it, and on arrival the code also reports the player's markers from the briefing. The server writes them as ordinary `marker_created` / `marker_updated` / `marker_deleted` records with the sender's unit as `owner` or `by`. A mission with its own `CfgRemoteExec` in whitelist mode needs `class aar_fnc_marker { allowedTargets = 2; };` under `Functions`.

## Radio

With ACRE2 or TFAR on the server, the recorder logs radio traffic. Both mods only know a player is transmitting on that player's own machine (the voice goes through TeamSpeak), so the server sends every machine with a player a small piece of code (`fn_radioClient.sqf`, via `remoteExecCall` and queued for players who join later; clients still need nothing installed). It listens to ACRE2's `acre_startedSpeaking` / `acre_stoppedSpeaking` and TFAR's `TFAR_event_OnTangent`, and reports each start and end with the radio, channel and frequency, plus every 5 s the radios the player carries when that changed. The server writes them as `radio_tx`, `radio_tx_end` and `radios`, stamped with server time, and drops a report about a unit the sending machine does not own.

- Only radio transmissions are logged, not direct speech or vehicle intercom.
- The reports reach the server through `remoteExecCall` of `aar_fnc_radio`. The addon allows it in its `CfgRemoteExec`; a mission with its own `CfgRemoteExec` in whitelist mode needs `class aar_fnc_radio { allowedTargets = 2; };` under `Functions`.
- A transmission whose end never arrives (the player disconnected mid-transmission) is shown for at most 30 s.

**TMF radio networks.** When a mission uses TMF's ACRE2 network settings (`TMF_AcreNetworkEnabled`), the `radio_nets` record holds them: each net has `index`, `sides`, `factions` and `channels`, and a channel is `{"name", "description", "radio", "shared", "number", "freq"}`. `number` is its channel number on that radio, and `freq` is read from the ACRE preset TMF builds for the network (`tmf_preset<index>`), so a `radio_tx` can be matched to a TMF channel by frequency. Units carry `radio_net` (the index) and `radio_channels` (indexes into that net's channels that TMF puts the unit on, by the channel's conditions or the unit's, group's or leader's channel list).

**Group markers.** With TMF, units carry their group's TMF group marker: `group_short`, its text (for example `A1` for the group `Alpha 1`), and `group_icon` and `group_size`, its icon and size textures (for example `x\tmf\addons\orbat\textures\blue_inf.paa` and `...\modif_dot.paa`). Include recordings when exporting `aar-icons.json` so these texture paths are collected. The viewer uses the recorded textures for TMF group and ORBAT markers when available, with a drawn-symbol fallback. Vanilla map marker textures and each marker class's resolved default RGBA and `showEditorMarkerColor` setting come from `aar-cfg.json`. A recorded `Default` marker color uses the marker class's exported default color; classes with `showEditorMarkerColor` disabled keep their texture's original colors. Older config exports without marker defaults use the viewer's built-in Arma palette and legacy flag behavior. Icon width, height, text, and alpha use the recorded marker properties. Without marker textures, the viewer falls back to simplified shapes. Map group markers have an independent **All sides / Sides with players** filter in the map layers menu. The Units roster (Groups and ORBAT) has its own **Show all** toggle, off by default. When off, it includes groups containing a current player or with an explicit TMF group marker, trims empty ORBAT teams/nodes, and limits vehicles to sides with a current player.

## Hits on players

A player's damage is decided on the player's own machine. The server's copy of the bullet usually agrees, but with lag it can hit or miss differently, so `proj_hit` on a player is the server's view of the shot. For the authoritative result `hit` comes from the `Hit` event on the machine that owns the object: the server for its own AI, and for players, headless client AI and the vehicles they drive, the owner's machine reports it to the server (`fn_hitClient.sqf`, sent as code like the other client reporters, so clients need nothing installed). The recorder does not use `MPHit`, because the engine broadcasts that to every machine on every hit. `killed` is always authoritative. `Hit` does not always fire for the killing blow.

## Kills and ACE medical

ACE medical kills units by script, often well after the shot (bleeding out, cardiac arrest), so the engine's `EntityKilled` usually names nobody or the victim as killer. With ACE loaded the server waits up to 3 s after a unit dies for ACE's `ace_killed` event, which ACE raises on every machine with the last unit that damaged the victim, and writes `killed` with that credit (`credit: "ace"`) and ACE's `cause`. Without it, the engine's killer is used (`credit: "engine"`). Either way, when that is nobody or the victim, the last recorded hit on the victim from someone else within five minutes (from `proj_hit`, `proj_splash` or `hit`) is credited instead (`credit: "last_hit"`). The weapon and distance come from the last hit by whoever is credited; a submunition (an artillery shell, a bomblet) counts from where its parent was fired.

Unconsciousness comes from ACE's `ace_unconscious` event, raised on every machine, so players need no reporter. Each snapshot also checks `lifeState` and ACE's `ACE_isUnconscious`, which catches vanilla incapacitation and anything the event missed.

## Other ACE events

With ACE loaded (and `logACE` on) the recorder also logs wounds, medical treatment, dragging and carrying, fireteam colours, captives, explosives and trip flares. ACE raises captive, explosive and trip flare events on every machine, so the server records them itself. Wounds (`ace_medical_woundReceived`), treatment (`ace_treatmentStarted`, `ace_treatmentSucceded`, `ace_treatmentFailed`), dragging (`ace_dragging_startedDrag` and the like) and fireteam colours (`ace_interaction_joinedTeam`) are raised only on the machine that owns the unit, so every machine runs `fn_aceClient.sqf` (sent as code like the other client reporters), which batches them to `aar_fnc_aceReport` four times a second. A report about a unit the sending machine does not own is dropped. A mission with its own `CfgRemoteExec` in whitelist mode needs `class aar_fnc_aceReport { allowedTargets = 2; };` under `Functions`.

Markers placed with ACE's marker tool are recorded like any other marker (`marker_created`), so `ace_markers_markerPlaced` is not used. Fireteam colours set without ACE's menu (the vanilla command menu, scripts) are not recorded.

## Lessons from other recorders

Before settling on this design we read OCAP2, R3 and Anrop's AAR addon. This one avoids what went wrong there:

- Strings go through `toJSON`, so names with quotes cannot break a record (R3, Anrop).
- Nothing is sent to clients and nothing a client sends is trusted; there is no admin event to spoof (OCAP).
- No scheduled script per projectile or per unit; everything runs in event handlers and one `EachFrame` handler (all three).
- Extension output is never `compile`d (R3), and the file is local, so there is no upload that can drop data or leak a token (Anrop, OCAP).
- Snapshots stop while a dedicated server is empty (R3, OCAP).
- New units and vehicles are registered by `EntityCreated` and removed by `EntityDeleted` the moment it happens, instead of scanning `allUnits` every second (R3, Anrop); a sweep on each keyframe is the safety net.

## Known limitations

- AI awareness records (`combat_mode`, `enemy_detected`, `fleeing`) come from group event handlers, which fire where the group is local. The server covers its own groups and sends every other machine (players and headless clients) `fn_groupClient.sqf`, which adds the same handlers to the groups local there (checked every 5 s) and reports to `aar_fnc_groupEvent`; a mission with its own `CfgRemoteExec` in whitelist mode needs `class aar_fnc_groupEvent { allowedTargets = 2; };`. `combat_mode` is only written when the behaviour changed, so a group moving between machines is not logged twice. The wiki doesn't document this locality, so it is an assumption to check in-game.

- `logProjectiles` writes two or three lines per round. Large firefights produce big files and cost some server FPS in SQF; turn it off if you only need movement and kills.
- Bullet impacts on terrain and buildings are not logged as hits, only as the `proj_end` position.
- Radio traffic needs the client code to arrive, so it starts a moment after a player loads in, and the server's time stamp is when the report arrived, not when the button was pressed.
- Needs Arma 3 2.18 or newer (`toJSON`, `ProjectileCreated` and the projectile event handlers).
- If a mission ends without `Ended` or `MPEnded` firing (for example leaving the editor preview), the file has no `end` line; the next mission closes it.
- Not tested in-game yet.
