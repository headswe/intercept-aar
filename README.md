# Intercept AAR Recorder

An [Intercept](https://intercept.github.io/) plugin for Arma 3 that records a mission for After Action Review. While a mission runs on the server it writes one line-delimited JSON file (`.jsonl`) containing periodic snapshots of every unit and vehicle plus the events that happened (kills, hits, every projectile from muzzle to impact, vehicle get in/out, player connects, markers).

## Building

Requires CMake 3.13+ and Visual Studio 2019/2022 (x64).

```
git clone --recursive <this repo>
cmake -S . -B out -A x64
cmake --build out --config Release
```

The DLL lands in `build/win64/Release/intercept_aar_x64.dll`. The GitHub Actions workflow in `.github/workflows/build.yml` builds the same thing on every push and uploads it as an artifact.

## Installing

Every build on GitHub Actions uploads an `@intercept_aar` artifact: the finished mod folder with the PBO and DLL in place. To assemble it yourself after building, run `python tools/pack_mod.py build/win64/Release/intercept_aar_x64.dll out`.

```
@intercept_aar/
  addons/intercept_aar_main.pbo
  intercept/intercept_aar_x64.dll
```

1. Get the Intercept mod (`@intercept`) from the Steam Workshop or the [Intercept releases](https://github.com/intercept/intercept/releases).
2. Start the server with both: `arma3server_x64.exe -serverMod=@intercept;@intercept_aar ...`. For a local test in the editor or singleplayer, use `-mod=@intercept;@intercept_aar` on the game instead.
3. Play a mission. The RPT log shows `[InterceptAAR] recording to ...` and the file appears under `aar\` in the Arma folder.

Only the server records; clients do not need the mod. In singleplayer or a hosted game the host records.

## Output

Files go to `<Arma working directory>/aar/` by default, or to the folder in the `AAR_OUTPUT_DIR` environment variable. One file per mission, named `YYYYMMDD-HHMMSS_<mission>_<world>.jsonl` (UTC).

Every line is a JSON object with `type` and `t` (mission time in seconds, from `time`). Positions are `[x, y, z]` ASL in metres. Entities are referred to by a numeric id that is stable for the whole recording; `0` means "none or unknown".

| type | fields |
|---|---|
| `header` | `version`, `mission`, `world`, `started_utc`, `interval`, `keyframe_interval`, `multiplayer` |
| `entity` | first sighting of an entity: `id`, `kind` (`unit`, `car`, `tank`, `heli`, `plane`, `ship`, `static`, `vehicle`, `air`), `class`, `display`, `side`; units also have `name`, `group`, `player`, `uid` |
| `snap` | `key` (true for a full keyframe), `e`: array of `[id, x, y, z, dir, alive, damage, vehicle_id]` |
| `killed` | `victim`, `killer`, `instigator`, `pos` |
| `hit` | `unit`, `source`, `instigator`, `damage` (server-local units only, see below) |
| `shot` | projectile created: `id` (projectile id), `shooter`, optional `parent` (for submunitions), optional `instigator` (the gunner when `shooter` is a vehicle), `weapon`, `ammo`, `pos`, `vel` |
| `submunition` | links a submunition (smoke or artillery shell, bomblet) recorded before its parent was known: `id`, `parent`, `shooter` |
| `proj_hit` | projectile directly hit a recorded unit or vehicle: `id`, `target`, `pos`, `part` (first component hit, e.g. `head`); one per projectile and target |
| `proj_splash` | explosive projectile damaged a recorded unit or vehicle: `id`, `target` |
| `proj_end` | projectile removed: `id`, `pos` (impact or end point), `exploded` |
| `get_in` / `get_out` | `vehicle`, `unit`, `role` (`driver`, `gunner`, `cargo`) |
| `group` | `unit`, `group`, `side` when a unit changes group or side |
| `player` | `unit`, `uid`, `name` when a player takes or leaves a unit (empty `uid` = now AI) |
| `respawn` | `new`, `old` |
| `connected` / `disconnected` | `uid`, `name`, `jip`, `owner` |
| `marker_created` / `marker_updated` / `marker_deleted` | `marker`, plus `text`, `markerType`, `color`, `channel`, `owner`, `pos` where available |
| `deleted` | `id` when an entity is removed from the world |
| `end` | `reason`, `entities` |

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

## Mission settings

Add this to a mission's `description.ext` to change the defaults (all optional):

```
class InterceptAAR {
    enabled = 1;            // 0 = do not record this mission
    interval = 1;           // seconds between snapshots
    keyframeInterval = 60;  // seconds between full snapshots
    logProjectiles = 1;     // shot / proj_hit / proj_splash / proj_end records
    logHits = 1;
    logMarkers = 1;
};
```

## How hits and projectiles are recorded

Projectiles use the projectile event handlers added in Arma 3 2.10+ (`HitPart`, `HitExplosion`, `Explode`, `Deleted`) together with the `ProjectileCreated` mission event handler. Intercept does not wrap these yet, so the plugin registers an SQF command, `interceptAARProjectile`, and adds the handlers with a small SQF snippet that forwards to it.

Shots are simulated on every machine (the same reason `Fired` fires for remote units), so the server's own copy of a player's bullet raises `HitPart` on the server too. That records hits on players on a dedicated server, which the old `Hit` event handler cannot do. `hit` is still logged for server-local units because it carries the damage amount.

## Known limitations

- `logProjectiles` writes two or three lines per round. Large firefights produce big files; turn it off if you only need movement and kills.
- Bullet impacts on terrain and buildings are not logged as hits, only as the `proj_end` position.
- Needs a current Arma 3 build: `ProjectileCreated` and the projectile event handlers do not exist in older versions.
- Recording hits on remote players this way has not been tested in-game yet.
- Intercept's upstream headers do not compile on Linux as-is, so the Linux server build is not supported yet. The plugin's own code was compile-checked against them with a few local header fixes.
