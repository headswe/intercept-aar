/*
 * postInit: opens the recording and adds the event handlers. Server only; in singleplayer
 * or a hosted game the host records.
 *
 * Mission settings in description.ext (all optional; class InterceptAAR is read too):
 *   class AAR { enabled = 1; interval = 1; keyframeInterval = 60; logProjectiles = 1; logHits = 1; logMarkers = 1;
 *               frameBudget = 2; spikeThreshold = 100; };
 */
if (!isServer) exitWith {};
aar_active = false;

private _cfg = missionConfigFile >> "AAR";
if (!isClass _cfg) then { _cfg = missionConfigFile >> "InterceptAAR" };
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

private _result = "arma_aar" callExtension ["open", [missionName, worldName]];
_result params ["_output", "_code"];
if (_output isEqualTo "" && _code == 0) exitWith {
    diag_log "[AAR] arma_aar extension did not load (is it whitelisted, or BattlEye off?)";
};
if (_code != 0) exitWith { diag_log format ["[AAR] %1", _output] };
(parseSimpleArray _output) params ["_path", "_startedUtc"];

aar_path = _path;
aar_buffer = [];
aar_entities = createHashMap;
aar_projShooters = createHashMap;  // projectile id -> shooter id while in flight
aar_nextId = 1;
aar_nextPid = 1;
aar_lastSnapshot = -1e9;
aar_lastKeyframe = -1e9;
aar_snap = [];          // snapshot in progress, see aar_fnc_snapshot
aar_snapStats = [0, 0, 0];
aar_batch = 100;        // entities per frame, adjusted to stay within aar_frameBudget
aar_lastWorkMs = 0;

["header", [
    "version", "1",
    "mission", toJSON missionName,
    "world", toJSON worldName,
    "started_utc", toJSON _startedUtc,
    "interval", aar_interval toFixed 2,
    "keyframe_interval", aar_keyframeInterval toFixed 2,
    "multiplayer", toJSON isMultiplayer
]] call aar_fnc_rec;

addMissionEventHandler ["EachFrame", { call aar_fnc_frame }];

addMissionEventHandler ["EntityKilled", {
    params ["_killed", "_killer", "_instigator"];
    if (!aar_active) exitWith {};
    private _victim = _killed call aar_fnc_id;
    if (_victim == 0) exitWith {};
    ["killed", [
        "victim", toJSON _victim,
        "killer", toJSON (_killer call aar_fnc_id),
        "instigator", toJSON (_instigator call aar_fnc_id),
        "pos", (getPosASL _killed) call aar_fnc_pos
    ]] call aar_fnc_rec;
}];

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
};

if (aar_logMarkers) then {
    addMissionEventHandler ["MarkerCreated", {
        params ["_marker", "_channel", "_owner"];
        if (!aar_active) exitWith {};
        ["marker_created", [
            "marker", toJSON _marker,
            "channel", toJSON _channel,
            "owner", toJSON (_owner call aar_fnc_id),
            "text", toJSON markerText _marker,
            "markerType", toJSON markerType _marker,
            "color", toJSON markerColor _marker,
            "pos", (getMarkerPos _marker) call aar_fnc_pos
        ]] call aar_fnc_rec;
    }];
    addMissionEventHandler ["MarkerUpdated", {
        params ["_marker"];
        if (!aar_active) exitWith {};
        ["marker_updated", [
            "marker", toJSON _marker,
            "text", toJSON markerText _marker,
            "pos", (getMarkerPos _marker) call aar_fnc_pos
        ]] call aar_fnc_rec;
    }];
    addMissionEventHandler ["MarkerDeleted", {
        params ["_marker"];
        if (!aar_active) exitWith {};
        ["marker_deleted", ["marker", toJSON _marker]] call aar_fnc_rec;
    }];
};

aar_active = true;
diag_log format ["[AAR] recording to %1", aar_path];
