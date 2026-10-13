/*
 * Handles the projectile event handlers added in aar_fnc_init.
 *
 * Arguments: 0: kind <STRING>, 1: projectile <OBJECT>, 2...: depends on kind
 *   "created": shooter, instigator, weapon, position, velocity
 *   "sub":     submunition
 *   "hit":     hit entity, position, components
 *   "splash":  hit entity
 *   "end":     position, exploded
 */
params ["_kind", "_projectile"];
if (!aar_active || {isNull _projectile}) exitWith {};

if (_kind isEqualTo "created") exitWith {
    _this params ["", "", "_shooterObj", "_instigatorObj", "_weapon", "_pos", "_vel"];
    private _pid = aar_nextPid;
    aar_nextPid = aar_nextPid + 1;
    _projectile setVariable ["aar_pid", _pid];
    private _shooter = _shooterObj call aar_fnc_id;
    private _instigator = _instigatorObj call aar_fnc_id;
    // Submunitions (artillery and smoke shells, cluster bomblets) have no shot parents of their own;
    // if the parent's SubmunitionCreated ran first it left the parent id on the projectile.
    private _parent = _projectile getVariable ["aar_parent", 0];
    if (_parent > 0 && _shooter == 0) then { _shooter = aar_projShooters getOrDefault [_parent, 0] };
    aar_projShooters set [_pid, _shooter];

    private _fields = ["id", toJSON _pid, "shooter", toJSON _shooter];
    if (_instigator != 0 && _instigator != _shooter) then { _fields append ["instigator", toJSON _instigator] };
    if (_parent > 0) then { _fields append ["parent", toJSON _parent] };
    _fields append [
        "weapon", toJSON _weapon,
        "ammo", toJSON typeOf _projectile,
        "pos", _pos call aar_fnc_pos,
        "vel", _vel call aar_fnc_pos
    ];
    ["shot", _fields] call aar_fnc_rec;
};

private _pid = _projectile getVariable ["aar_pid", 0];
if (_pid <= 0) exitWith {};

if (_kind isEqualTo "sub") exitWith {
    private _sub = _this select 2;
    if (isNull _sub) exitWith {};
    private _sid = _sub getVariable ["aar_pid", 0];
    // ProjectileCreated has not run for it yet; it will pick the parent up from this variable.
    if (_sid <= 0) exitWith { _sub setVariable ["aar_parent", _pid] };
    private _shooter = aar_projShooters getOrDefault [_pid, 0];
    if (_sid in aar_projShooters) then { aar_projShooters set [_sid, _shooter] };
    ["submunition", ["id", toJSON _sid, "parent", toJSON _pid, "shooter", toJSON _shooter]] call aar_fnc_rec;
};

if (_kind in ["hit", "splash"]) exitWith {
    // Only hits on recorded units and vehicles; bullets striking terrain or buildings are not logged.
    private _target = (_this select 2) call aar_fnc_knownId;
    if (_target <= 0) exitWith {};
    private _fields = ["id", toJSON _pid, "target", toJSON _target];
    // HitPart fires once per component the bullet passes through, so several lines for the
    // same projectile and target trace its path through the body.
    if (_kind isEqualTo "hit") then {
        _fields append ["pos", (_this select 3) call aar_fnc_pos];
        private _parts = _this select 4;
        if (_parts isNotEqualTo []) then { _fields append ["part", toJSON (_parts select 0)] };
    };
    [["proj_splash", "proj_hit"] select (_kind isEqualTo "hit"), _fields] call aar_fnc_rec;
};

if (_kind isEqualTo "end") exitWith {
    ["proj_end", ["id", toJSON _pid, "pos", (_this select 2) call aar_fnc_pos, "exploded", toJSON (_this select 3)]] call aar_fnc_rec;
    aar_projShooters deleteAt _pid;
};
