/*
 * postInit: opens the recording and adds the event handlers. Server only; in singleplayer
 * or a hosted game the host records.
 *
 * Mission settings in description.ext (all optional):
 *   class AAR { enabled = 1; interval = 1; keyframeInterval = 60; logProjectiles = 1; logHits = 1; logMarkers = 1;
 *               frameBudget = 2; spikeThreshold = 100; pauseWhenEmpty = 1; logAI = 1; enemyDetectedCooldown = 120; logRadio = 1;
 *               logChat = 1; netInterval = 10; };
 */
if (!isServer) exitWith {};
aar_active = false;

private _cfg = missionConfigFile >> "AAR";
private _setting = {
    params ["_key", "_default"];
    private _entry = _cfg >> _key;
    if (isNumber _entry) then { getNumber _entry } else { _default }
};
if ((["enabled", 1] call _setting) == 0) exitWith { diag_log "[AAR] disabled by mission config" };

aar_interval = (["interval", 1] call _setting) max 0.1;
aar_keyframeInterval = (["keyframeInterval", 60] call _setting) max aar_interval;
aar_logProjectiles = (["logProjectiles", 1] call _setting) != 0;
aar_logHits = (["logHits", 1] call _setting) != 0;
aar_logMarkers = (["logMarkers", 1] call _setting) != 0;
aar_frameBudget = (["frameBudget", 2] call _setting) max 0.1;          // ms of recorder work per frame
aar_spikeThreshold = (["spikeThreshold", 100] call _setting) max 1;  // ms; slower server frames are logged
aar_pauseWhenEmpty = (["pauseWhenEmpty", 1] call _setting) != 0;
aar_logAI = (["logAI", 1] call _setting) != 0;  // AI group behaviour, enemies detected, fleeing
aar_enemyDetectedCooldown = (["enemyDetectedCooldown", 120] call _setting) max 0;  // s before a group's same target is logged again
aar_logChat = (["logChat", 1] call _setting) != 0;  // chat on every channel
aar_netInterval = (["netInterval", 10] call _setting) max 0;  // s between net records; 0 = off
aar_tmf = isClass (configFile >> "CfgPatches" >> "tmf_common");  // TMF ORBAT and loadouts
aar_logRadio = (["logRadio", 1] call _setting) != 0 && {isClass (configFile >> "CfgPatches" >> "acre_main") || isClass (configFile >> "CfgPatches" >> "tfar_core")};
// TMF's ACRE2 radio networks, when the mission uses them.
aar_tmfNets = [];
if (aar_tmf && aar_logRadio && {(getMissionConfigValue ["TMF_AcreNetworkEnabled", false]) in [true, 1]}) then {
    aar_tmfNets = getMissionConfigValue ["TMF_AcreSettings", []];
    if (aar_tmfNets isEqualType "") then { aar_tmfNets = if (aar_tmfNets isEqualTo "") then { [] } else { call compile aar_tmfNets } };
    if (isNil "aar_tmfNets" || {!(aar_tmfNets isEqualType [])}) then { aar_tmfNets = [] };
};

private _result = "arma_aar" callExtension ["open", [missionName, worldName]];
_result params ["_output", "_code"];
// A failed load returns no output; the code is 0 on some versions and an error code on others.
if (_output isEqualTo "") exitWith {
    diag_log format ["[AAR] arma_aar extension did not load (code %1). Is arma_aar_x64.dll / arma_aar_x64.so in the mod folder, and BattlEye off?", _code];
};
if (_code != 0) exitWith { diag_log format ["[AAR] %1", _output] };
(parseSimpleArray _output) params ["_path", "_startedUtc"];

private _missionText = {
    params ["_key"];
    private _text = getMissionConfigValue [_key, ""];
    if !(_text isEqualType "") then { _text = str _text };
    if (_text select [0, 5] == "$STR_") then { localize (_text select [1]) } else { _text }
};

aar_path = _path;
aar_buffer = [];
aar_entities = createHashMap;
aar_leaders = createHashMap;            // "side|group" -> id of its leader, see aar_fnc_snapshot
aar_projShooters = createHashMap;  // projectile id -> shooter id while in flight
aar_projShots = createHashMap;     // projectile id -> [weapon, origin, instigator id] while in flight
aar_lastHits = createHashMap;      // entity id -> its last hit, see aar_fnc_lastHit
aar_pendingKills = createHashMap;  // victim id -> killed waiting for ACE's credit, see EntityKilled
aar_aceMedical = isClass (configFile >> "CfgPatches" >> "ace_medical_status");
aar_nextId = 1;
aar_nextPid = 1;
aar_lastSnapshot = -1e9;
aar_lastNet = -1e9;
aar_lastKeyframe = -1e9;
aar_snap = [];          // snapshot in progress, see aar_fnc_snapshot
aar_snapStats = [0, 0, 0];
aar_batch = 100;        // entities per frame, adjusted to stay within aar_frameBudget
aar_lastWorkMs = 0;
aar_idle = false;
aar_radioOpen = createHashMap;          // "unit radio" -> true while a transmission is open
// Ammo that only exists as a submunition of another shot (artillery and smoke shells, bomblets).
aar_subAmmo = createHashMap;
{
    private _sub = _x >> "submunitionAmmo";
    { if (_x isEqualType "" && {_x isNotEqualTo ""}) then { aar_subAmmo set [toLowerANSI _x, true] } }
        forEach ([getArray _sub, [getText _sub]] select (isText _sub));
} forEach ("isText (_x >> 'submunitionAmmo') || {isArray (_x >> 'submunitionAmmo')}" configClasses (configFile >> "CfgAmmo"));
aar_remoteProj = createHashMap;         // "client owner:client projectile id" -> projectile id, see aar_fnc_projectileReport
aar_radioNetsPending = aar_tmfNets isNotEqualTo [];  // radio_nets is written once TMF built its presets

["header", [
    "version", "1",
    "mission", toJSON missionName,
    "world", toJSON worldName,
    "started_utc", toJSON _startedUtc,
    "interval", aar_interval toFixed 2,
    "keyframe_interval", aar_keyframeInterval toFixed 2,
    "net_interval", aar_netInterval toFixed 2,
    "multiplayer", toJSON isMultiplayer,
    // Mission metadata. Text from description.ext is localized when it is a $STR key.
    "briefing_name", toJSON briefingName,
    "on_load_name", toJSON (["onLoadName"] call _missionText),
    "author", toJSON (["author"] call _missionText),
    "overview", toJSON (["overviewText"] call _missionText),
    "game_type", toJSON getText (missionConfigFile >> "Header" >> "gameType"),
    "max_players", toJSON getNumber (missionConfigFile >> "Header" >> "maxPlayers"),
    "server_name", toJSON serverName,
    "world_name", toJSON getText (configFile >> "CfgWorlds" >> worldName >> "description"),
    "world_size", toJSON worldSize,
    "date", toJSON date,
    "time_multiplier", timeMultiplier toFixed 2,
    "weather", toJSON [overcast, fog, rain],
    "game_version", toJSON (productVersion select [2, 2]),
    "mods", toJSON ((getLoadedModsInfo select { !(_x select 3) }) apply { _x select 1 })
]] call aar_fnc_rec;

if (aar_tmf) then { call aar_fnc_orbat };

if (aar_logHits) then {
    [[], aar_fnc_hitClient] remoteExecCall ["call", -2, "aar_hitClient"];
};

if (aar_logAI) then {
    // Group AI events fire only where the group is local, so players' and headless clients'
    // machines get the client half as code and report their own groups.
    [[aar_enemyDetectedCooldown], aar_fnc_groupClient] remoteExecCall ["call", -2, "aar_groupClient"];
};

if (aar_logRadio) then {
    // ACRE2 and TFAR raise transmissions only on the speaker's machine, so every machine with a
    // player gets the client half as code (no mod needed there), queued for players joining later.
    [[], aar_fnc_radioClient] remoteExecCall ["call", [0, -2] select isDedicated, "aar_radioClient"];
};

addMissionEventHandler ["EachFrame", { call aar_fnc_frame }];

addMissionEventHandler ["EntityCreated", {
    params ["_entity"];
    if (!aar_active) exitWith {};
    _entity call aar_fnc_id;
}];

addMissionEventHandler ["EntityDeleted", {
    params ["_entity"];
    if (!aar_active) exitWith {};
    private _id = _entity call aar_fnc_knownId;
    if (_id == 0) exitWith {};
    ["deleted", ["id", toJSON _id]] call aar_fnc_rec;
    aar_entities deleteAt _id;
}];

addMissionEventHandler ["BuildingChanged", {
    params ["_from", "_to", "_isRuin"];
    if (!aar_active) exitWith {};
    ["building", [
        "from", toJSON typeOf _from,
        "to", toJSON typeOf _to,
        "ruin", toJSON _isRuin,
        "pos", (getPosASL ([_to, _from] select isNull _to)) call aar_fnc_pos
    ]] call aar_fnc_rec;
}];

addMissionEventHandler ["EntityKilled", {
    params ["_killed", "_killer", "_instigator"];
    if (!aar_active) exitWith {};
    private _victim = _killed call aar_fnc_id;
    if (_victim == 0) exitWith {};
    if (aar_aceMedical && {_killed isKindOf "CAManBase"}) exitWith {
        // ACE medical kills by script, so the engine's killer is often nobody or the victim. ACE
        // raises ace_killed with its own credit on the unit's machine, which reaches the server
        // just before or after this; the record waits for it (written by the frame handler after
        // 3 s without it, with the engine's credit).
        private _ace = _killed getVariable "aar_aceKilled";
        if (isNil "_ace") exitWith { aar_pendingKills set [_victim, [_killed, _killer, _instigator, time, getPosASL _killed]] };
        _ace params ["_cause", "_aceKiller", "_aceInstigator"];
        [_killed, [_aceKiller, _killer] select (isNull _aceKiller), [_aceInstigator, _instigator] select (isNull _aceInstigator), "ace", _cause, time, getPosASL _killed] call aar_fnc_killed;
    };
    [_killed, _killer, _instigator, "engine", "", time, getPosASL _killed] call aar_fnc_killed;
}];

if (aar_aceMedical) then {
    ["ace_killed", {
        params [["_unit", objNull, [objNull]], ["_cause", "", [""]], ["_killer", objNull, [objNull]], ["_instigator", objNull, [objNull]]];
        if (!aar_active || {isNull _unit}) exitWith {};
        private _victim = _unit getVariable ["aar_id", 0];
        private _pending = aar_pendingKills getOrDefault [_victim, []];
        if (_pending isEqualTo []) exitWith { _unit setVariable ["aar_aceKilled", [_cause, _killer, _instigator]] };
        aar_pendingKills deleteAt _victim;
        _pending params ["_obj", "_engineKiller", "_engineInstigator", "_time", "_pos"];
        [_obj, [_killer, _engineKiller] select (isNull _killer), [_instigator, _engineInstigator] select (isNull _instigator), "ace", _cause, _time, _pos] call aar_fnc_killed;
    }] call CBA_fnc_addEventHandler;
    // Raised on every machine, so the server sees it for players too.
    ["ace_unconscious", {
        params [["_unit", objNull, [objNull]], ["_state", false, [false]]];
        [_unit, _state] call aar_fnc_unconscious;
    }] call CBA_fnc_addEventHandler;
};

addMissionEventHandler ["EntityRespawned", {
    params ["_new", "_old"];
    if (!aar_active) exitWith {};
    ["respawn", ["new", toJSON (_new call aar_fnc_id), "old", toJSON (_old call aar_fnc_id)]] call aar_fnc_rec;
}];

addMissionEventHandler ["PlayerConnected", {
    params ["", "_uid", "_name", "_jip", "_owner"];
    if (!aar_active) exitWith {};
    ["connected", ["uid", toJSON _uid, "name", toJSON _name, "jip", toJSON _jip, "owner", toJSON _owner]] call aar_fnc_rec;
}];

addMissionEventHandler ["PlayerDisconnected", {
    params ["", "_uid", "_name", "_jip", "_owner"];
    if (!aar_active) exitWith {};
    ["disconnected", ["uid", toJSON _uid, "name", toJSON _name, "jip", toJSON _jip, "owner", toJSON _owner]] call aar_fnc_rec;
}];

addMissionEventHandler ["MPEnded", { ["mp_ended"] call aar_fnc_stop }];
addMissionEventHandler ["Ended", {
    params ["_endType"];
    ["ended:" + _endType] call aar_fnc_stop;
}];

if (aar_logProjectiles) then {
    addMissionEventHandler ["ProjectileCreated", {
        params ["_projectile"];
        if (!aar_active) exitWith {};
        (getShotParents _projectile) params [["_shooter", objNull], ["_instigator", objNull]];
        // Only the firing machine's copy of a projectile hits and ends reliably, so projectiles
        // fired by players and headless client AI are reported by that machine (aar_fnc_projectileClient).
        private _firer = [_instigator, _shooter] select (isNull _instigator);
        if (isMultiplayer && {!isNull _firer} && {!local _firer}) exitWith {};
        private _weapon = "";
        if (!isNull _shooter) then {
            _weapon = if (_shooter isKindOf "CAManBase") then {
                currentWeapon _shooter
            } else {
                private _turret = if (isNull _instigator) then { [-1] } else { _shooter unitTurret _instigator };
                _shooter currentWeaponTurret _turret
            };
        };
        ["created", _projectile, _shooter, _instigator, _weapon, getPosASL _projectile, velocity _projectile] call aar_fnc_projectile;
        _projectile addEventHandler ["SubmunitionCreated", {
            params ["_projectile", "_submunition"];
            ["sub", _projectile, _submunition] call aar_fnc_projectile;
        }];
        _projectile addEventHandler ["HitPart", {
            params ["_projectile", "_hitEntity", "", "_pos", "", "", "_components"];
            ["hit", _projectile, _hitEntity, _pos, _components] call aar_fnc_projectile;
        }];
        _projectile addEventHandler ["HitExplosion", {
            params ["_projectile", "_hitEntity"];
            ["splash", _projectile, _hitEntity] call aar_fnc_projectile;
        }];
        _projectile addEventHandler ["Explode", {
            (_this select 0) setVariable ["aar_exploded", true];
        }];
        _projectile addEventHandler ["Deleted", {
            params ["_projectile"];
            ["end", _projectile, getPosASL _projectile, _projectile getVariable ["aar_exploded", false]] call aar_fnc_projectile;
        }];
    }];
    [[], aar_fnc_projectileClient] remoteExecCall ["call", -2, "aar_projectileClient"];
};

if (aar_logMarkers) then {
    // Every marker players can see, whoever made it; see aar_fnc_skipMarker for what is left out.
    addMissionEventHandler ["MarkerCreated", {
        params ["_marker", "_channel", "_owner"];
        if (!aar_active || {_marker call aar_fnc_skipMarker}) exitWith {};
        ["marker_created", (_marker call aar_fnc_markerFields) + [
            "channel", toJSON _channel,
            "owner", toJSON (_owner call aar_fnc_id)
        ]] call aar_fnc_rec;
    }];
    addMissionEventHandler ["MarkerUpdated", {
        params ["_marker"];
        if (!aar_active || {_marker call aar_fnc_skipMarker}) exitWith {};
        ["marker_updated", _marker call aar_fnc_markerFields] call aar_fnc_rec;
    }];
    addMissionEventHandler ["MarkerDeleted", {
        params ["_marker", "", ["_deleter", objNull]];
        if (!aar_active || {_marker call aar_fnc_skipMarker}) exitWith {};
        private _fields = ["marker", toJSON _marker];
        if (!isNull _deleter) then { _fields append ["by", toJSON (_deleter call aar_fnc_id)] };
        ["marker_deleted", _fields] call aar_fnc_rec;
    }];
    // Markers that exist before the recording starts: those placed in the editor and any a
    // script made during init.
    {
        if (_x call aar_fnc_skipMarker) then { continue };
        ["marker_created", (_x call aar_fnc_markerFields) + [
            "channel", toJSON markerChannel _x,
            "editor", "true"
        ]] call aar_fnc_rec;
    } forEach allMapMarkers;
    // Players' markers on channels other than Global never reach the server, so every machine
    // with a player gets the client half as code (no mod needed there) and reports its own.
    [[], aar_fnc_markerClient] remoteExecCall ["call", [0, -2] select isDedicated, "aar_markerClient"];
};

if (aar_logChat) then {
    // Messages the server sees itself that no player typed: system messages and chat from server
    // scripts (globalChat, sideChat, systemChat...). Player messages are reported by the player
    // who typed them (aar_fnc_chatClient), since most channels never reach a dedicated server.
    addMissionEventHandler ["HandleChatMessage", {
        params ["_channel", "", "_from", "_text", "_person", "_name", "", "", "_isPlayerMessage"];
        if (aar_active && {!_isPlayerMessage} && {_text isNotEqualTo ""}) then {
            [_channel, _person, _name, _from, _text, false] call aar_fnc_chat;
        };
        nil  // anything else returned would change or hide the message
    }];
    [[], aar_fnc_chatClient] remoteExecCall ["call", [0, -2] select isDedicated, "aar_chatClient"];
};

true call aar_fnc_coverMap;

aar_active = true;
diag_log format ["[AAR] recording to %1", aar_path];
