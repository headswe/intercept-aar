/*
 * Client side of the projectile recording. The server sends this code to every other machine
 * (players and headless clients, aar_fnc_init), so clients need nothing installed; it must not
 * call any other aar_ function, because clients don't have them.
 *
 * A projectile is simulated on every machine, but only the copy on the machine that fired it is
 * authoritative: there it hits, explodes and ends; the server's copy of a player's bullet never
 * reports a hit and often has no end. So this machine records the projectiles its own units fire
 * (its player, AI in that player's group, headless client AI) and sends them to the server
 * (aar_fnc_projectileReport) in batches a few times a second. Each entry carries how long ago it
 * happened, so the server can stamp it with the right time.
 *
 * Entries, with a per-machine projectile id:
 *   ["shot", id, shooter, instigator, weapon, ammo, position, velocity, age]
 *   ["sub", id, parent id, ammo, position, velocity, age]   a submunition of a shot
 *   ["hit", id, hit object, position, component, age]
 *   ["splash", id, hit object, age]
 *   ["end", id, position, exploded, age]
 */
if (isServer || {!isNil "aar_pc_ready"}) exitWith {};
aar_pc_ready = true;
aar_pc_nextId = 1;
aar_pc_buffer = [];
aar_pc_flushAt = 0;

aar_pc_attach = {
    params ["_projectile", "_id"];
    _projectile setVariable ["aar_pc_id", _id];
    _projectile addEventHandler ["SubmunitionCreated", {
        params ["_projectile", "_submunition"];
        if (isNull _submunition) exitWith {};
        private _sid = aar_pc_nextId;
        aar_pc_nextId = aar_pc_nextId + 1;
        aar_pc_buffer pushBack ["sub", _sid, _projectile getVariable ["aar_pc_id", 0], typeOf _submunition,
            getPosASL _submunition, velocity _submunition, diag_tickTime];
        [_submunition, _sid] call aar_pc_attach;
    }];
    _projectile addEventHandler ["HitPart", {
        params ["_projectile", "_hitEntity", "", "_pos", "", "", "_components"];
        if (isNull _hitEntity) exitWith {};
        aar_pc_buffer pushBack ["hit", _projectile getVariable ["aar_pc_id", 0], _hitEntity, _pos, _components param [0, ""], diag_tickTime];
    }];
    _projectile addEventHandler ["HitExplosion", {
        params ["_projectile", "_hitEntity"];
        if (isNull _hitEntity) exitWith {};
        aar_pc_buffer pushBack ["splash", _projectile getVariable ["aar_pc_id", 0], _hitEntity, diag_tickTime];
    }];
    _projectile addEventHandler ["Explode", {
        (_this select 0) setVariable ["aar_pc_exploded", true];
    }];
    _projectile addEventHandler ["Deleted", {
        params ["_projectile"];
        aar_pc_buffer pushBack ["end", _projectile getVariable ["aar_pc_id", 0], getPosASL _projectile,
            _projectile getVariable ["aar_pc_exploded", false], diag_tickTime];
    }];
};

addMissionEventHandler ["ProjectileCreated", {
    params ["_projectile"];
    (getShotParents _projectile) params [["_shooter", objNull], ["_instigator", objNull]];
    // The gunner fires a vehicle's weapon; without one (a submunition) the parent shot reports it.
    private _firer = [_instigator, _shooter] select (isNull _instigator);
    if (isNull _firer || {!local _firer}) exitWith {};
    private _weapon = if (_shooter isKindOf "CAManBase") then {
        currentWeapon _shooter
    } else {
        _shooter currentWeaponTurret (if (isNull _instigator) then { [-1] } else { _shooter unitTurret _instigator })
    };
    private _id = aar_pc_nextId;
    aar_pc_nextId = aar_pc_nextId + 1;
    aar_pc_buffer pushBack ["shot", _id, _shooter, _instigator, _weapon, typeOf _projectile,
        getPosASL _projectile, velocity _projectile, diag_tickTime];
    [_projectile, _id] call aar_pc_attach;
}];

addMissionEventHandler ["EachFrame", {
    if (aar_pc_buffer isEqualTo [] || {diag_tickTime < aar_pc_flushAt}) exitWith {};
    aar_pc_flushAt = diag_tickTime + 0.25;
    private _now = diag_tickTime;
    // The last element of every entry is when it happened; send how long ago instead.
    private _batch = aar_pc_buffer apply { _x set [count _x - 1, _now - (_x select -1)]; _x };
    aar_pc_buffer = [];
    for "_i" from 0 to count _batch - 1 step 200 do {
        [_batch select [_i, 200]] remoteExecCall ["aar_fnc_projectileReport", 2];
    };
}];
