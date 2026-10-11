/*
 * Gives a new unit or vehicle its id, writes its entity record and adds its event handlers.
 * Other objects (weapon holders, crates, logics) are marked ignored.
 *
 * Arguments: object <OBJECT>
 * Returns: id, or 0 when ignored <NUMBER>
 */
params ["_obj"];

private _kind = call {
    if (_obj isKindOf "CAManBase") exitWith {"unit"};
    if (_obj isKindOf "StaticWeapon") exitWith {"static"};
    if (_obj isKindOf "Tank") exitWith {"tank"};
    if (_obj isKindOf "Car") exitWith {"car"};
    if (_obj isKindOf "Helicopter") exitWith {"heli"};
    if (_obj isKindOf "Plane") exitWith {"plane"};
    if (_obj isKindOf "Ship") exitWith {"ship"};
    if (_obj isKindOf "LandVehicle") exitWith {"vehicle"};
    if (_obj isKindOf "Air") exitWith {"air"};
    ""
};
if (_kind isEqualTo "") exitWith {
    _obj setVariable ["aar_id", -1];
    0
};

private _id = aar_nextId;
aar_nextId = aar_nextId + 1;
_obj setVariable ["aar_id", _id];

private _isUnit = _kind isEqualTo "unit";
private _class = typeOf _obj;
private _side = str side _obj;
private _group = if (_isUnit && {!isNull group _obj}) then { groupId group _obj } else { "" };
private _uid = if (isPlayer _obj) then { getPlayerUID _obj } else { "" };
// [object, kind, group, side, uid, last snapshot state]
aar_entities set [_id, [_obj, _kind, _group, _side, _uid, []]];

private _fields = [
    "id", str _id,
    "kind", str _kind,
    "class", str _class,
    "display", str getText (configFile >> "CfgVehicles" >> _class >> "displayName"),
    "side", str _side
];
if (_isUnit) then {
    _fields append ["name", str name _obj, "group", str _group, "player", str (_uid isNotEqualTo ""), "uid", str _uid];
};
["entity", _fields] call aar_fnc_rec;

if (aar_logHits) then {
    // Hit only fires where the unit is local (AI on the server). Hits on remote players
    // come from the projectile HitPart handler, which fires on the server's copy of every shot.
    _obj addEventHandler ["Hit", {
        params ["_unit", "_source", "_damage", "_instigator"];
        if (!aar_active) exitWith {};
        ["hit", [
            "unit", str (_unit call aar_fnc_knownId),
            "source", str (_source call aar_fnc_id),
            "instigator", str (_instigator call aar_fnc_id),
            "damage", _damage toFixed 2
        ]] call aar_fnc_rec;
    }];
};

if (!_isUnit) then {
    _obj addEventHandler ["GetIn", {
        params ["_vehicle", "_role", "_unit"];
        if (!aar_active) exitWith {};
        _role = toLowerANSI _role;
        if !(_role in ["driver", "gunner"]) then { _role = "cargo" };
        ["get_in", ["vehicle", str (_vehicle call aar_fnc_knownId), "unit", str (_unit call aar_fnc_id), "role", str _role]] call aar_fnc_rec;
    }];
    _obj addEventHandler ["GetOut", {
        params ["_vehicle", "_role", "_unit"];
        if (!aar_active) exitWith {};
        _role = toLowerANSI _role;
        if !(_role in ["driver", "gunner"]) then { _role = "cargo" };
        ["get_out", ["vehicle", str (_vehicle call aar_fnc_knownId), "unit", str (_unit call aar_fnc_id), "role", str _role]] call aar_fnc_rec;
    }];
};

_id
