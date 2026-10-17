/*
 * Writes a batch of projectile reports from a client (sent by the code in
 * aar_fnc_projectileClient): the projectiles fired by units local to that machine, which the
 * server leaves out of its own projectile recording. Shots by a unit the sending machine does
 * not own are dropped, and so is anything about a projectile whose shot was not accepted.
 *
 * Arguments: 0: entries <ARRAY>, see aar_fnc_projectileClient
 */
params [["_batch", [], [[]]]];
if (!aar_active || {!aar_logProjectiles}) exitWith {};
private _sender = if (isMultiplayer && {isRemoteExecuted}) then { remoteExecutedOwner } else { -1 };
private _key = { str _sender + ":" + str _this };
private _num = { params ["_v", ["_default", 0]]; [_default, _v] select (_v isEqualType 0) };
private _vec = { ((_this param [0, [], [[]]]) select [0, 3]) apply { [0, _x] select (_x isEqualType 0) } };

{
    if !(_x isEqualType []) then { continue };
    private _kind = _x param [0, "", [""]];
    private _time = time - ((((_x select -1) call _num) max 0) min 5);
    switch (_kind) do {
        case "shot": {
            _x params ["", ["_cid", 0, [0]], ["_shooterObj", objNull, [objNull]], ["_instigatorObj", objNull, [objNull]],
                ["_weapon", "", [""]], ["_ammo", "", [""]], ["_pos", [], [[]]], ["_vel", [], [[]]]];
            private _firer = [_instigatorObj, _shooterObj] select (isNull _instigatorObj);
            if (isNull _firer || {_sender >= 0 && {owner _firer != _sender}}) then { continue };
            private _pid = aar_nextPid;
            aar_nextPid = aar_nextPid + 1;
            aar_remoteProj set [_cid call _key, _pid];
            private _shooter = _shooterObj call aar_fnc_id;
            private _instigator = _instigatorObj call aar_fnc_id;
            aar_projShooters set [_pid, _shooter];
            private _fields = ["id", toJSON _pid, "shooter", toJSON _shooter];
            if (_instigator != 0 && _instigator != _shooter) then { _fields append ["instigator", toJSON _instigator] };
            _fields append ["weapon", toJSON (_weapon select [0, 64]), "ammo", toJSON (_ammo select [0, 64]),
                "pos", [_pos] call _vec call aar_fnc_pos, "vel", [_vel] call _vec call aar_fnc_pos];
            ["shot", _fields, _time] call aar_fnc_rec;
        };
        case "sub": {
            _x params ["", ["_cid", 0, [0]], ["_parentCid", 0, [0]], ["_ammo", "", [""]], ["_pos", [], [[]]], ["_vel", [], [[]]]];
            private _parent = aar_remoteProj getOrDefault [_parentCid call _key, 0];
            if (_parent <= 0) then { continue };
            private _pid = aar_nextPid;
            aar_nextPid = aar_nextPid + 1;
            aar_remoteProj set [_cid call _key, _pid];
            private _shooter = aar_projShooters getOrDefault [_parent, 0];
            aar_projShooters set [_pid, _shooter];
            ["shot", ["id", toJSON _pid, "shooter", toJSON _shooter, "parent", toJSON _parent, "weapon", toJSON "",
                "ammo", toJSON (_ammo select [0, 64]), "pos", [_pos] call _vec call aar_fnc_pos, "vel", [_vel] call _vec call aar_fnc_pos], _time] call aar_fnc_rec;
        };
        case "hit";
        case "splash": {
            // A splash entry is [kind, id, object, age]; only a hit carries a position and component.
            _x params ["", ["_cid", 0, [0]], ["_hitObj", objNull, [objNull]]];
            private _pid = aar_remoteProj getOrDefault [_cid call _key, 0];
            if (_pid <= 0) then { continue };
            // Only hits on recorded units and vehicles, as for the server's own projectiles.
            private _target = _hitObj call aar_fnc_knownId;
            if (_target <= 0) then { continue };
            private _fields = ["id", toJSON _pid, "target", toJSON _target];
            if (_kind == "hit") then {
                _x params ["", "", "", ["_pos", [], [[]]], ["_part", "", [""]]];
                _fields append ["pos", [_pos] call _vec call aar_fnc_pos];
                if (_part isNotEqualTo "") then { _fields append ["part", toJSON (_part select [0, 64])] };
            };
            [["proj_splash", "proj_hit"] select (_kind == "hit"), _fields, _time] call aar_fnc_rec;
        };
        case "end": {
            _x params ["", ["_cid", 0, [0]], ["_pos", [], [[]]], ["_exploded", false, [false]]];
            private _pid = aar_remoteProj getOrDefault [_cid call _key, 0];
            if (_pid <= 0) then { continue };
            aar_remoteProj deleteAt (_cid call _key);
            ["proj_end", ["id", toJSON _pid, "pos", [_pos] call _vec call aar_fnc_pos, "exploded", toJSON _exploded], _time] call aar_fnc_rec;
            aar_projShooters deleteAt _pid;
        };
    };
} forEach (_batch select [0, 500]);
