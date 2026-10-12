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
    "id", toJSON _id,
    "kind", toJSON _kind,
    "class", toJSON _class,
    "display", toJSON getText (configFile >> "CfgVehicles" >> _class >> "displayName"),
    "side", toJSON _side
];
if (_isUnit) then {
    _fields append ["name", toJSON name _obj, "group", toJSON _group, "player", toJSON (_uid isNotEqualTo ""), "uid", toJSON _uid];
};
["entity", _fields] call aar_fnc_rec;

if (aar_logHits) then {
    // Hit fires only where the object is local, so it covers server AI. Once the object is
    // remote (a player, headless client AI) the server switches to MPHit, which the owner raises
    // and broadcasts, so the hit is the owner's authoritative result rather than the server's
    // copy of the bullet.
    _obj addEventHandler ["Hit", {
        params ["_unit"];
        if (_unit getVariable ["aar_mpHit", false]) exitWith {};
        _this call aar_fnc_hit;
    }];
    if (!local _obj) then { _obj call aar_fnc_addMPHit };
    _obj addEventHandler ["Local", {
        params ["_entity", "_isLocal"];
        if (!_isLocal) then { _entity call aar_fnc_addMPHit };
    }];
};

if (!_isUnit) then {
    _obj addEventHandler ["GetIn", {
        params ["_vehicle", "_role", "_unit"];
        if (!aar_active) exitWith {};
        _role = toLowerANSI _role;
        if !(_role in ["driver", "gunner"]) then { _role = "cargo" };
        ["get_in", ["vehicle", toJSON (_vehicle call aar_fnc_knownId), "unit", toJSON (_unit call aar_fnc_id), "role", toJSON _role]] call aar_fnc_rec;
    }];
    _obj addEventHandler ["GetOut", {
        params ["_vehicle", "_role", "_unit", "", ["_isEject", false]];
        if (!aar_active) exitWith {};
        _role = toLowerANSI _role;
        if !(_role in ["driver", "gunner"]) then { _role = "cargo" };
        private _fields = ["vehicle", toJSON (_vehicle call aar_fnc_knownId), "unit", toJSON (_unit call aar_fnc_id), "role", toJSON _role];
        if (_isEject) then { _fields append ["eject", "true"] };
        ["get_out", _fields] call aar_fnc_rec;
    }];
    // Moving between seats inside the vehicle raises neither GetIn nor GetOut.
    _obj addEventHandler ["SeatSwitched", {
        params ["_vehicle", "_unit1", "_unit2"];
        if (!aar_active) exitWith {};
        {
            if (!isNull _x) then {
                private _role = toLowerANSI ((assignedVehicleRole _x) param [0, "cargo"]);
                if (_role isEqualTo "turret") then { _role = "gunner" };
                if !(_role in ["driver", "gunner"]) then { _role = "cargo" };
                ["seat", ["vehicle", toJSON (_vehicle call aar_fnc_knownId), "unit", toJSON (_x call aar_fnc_id), "role", toJSON _role]] call aar_fnc_rec;
            };
        } forEach [_unit1, _unit2];
    }];
};

_id
