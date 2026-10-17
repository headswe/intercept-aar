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
// [object, kind, group, side, uid, last snapshot state, TMF role]
aar_entities set [_id, [_obj, _kind, _group, _side, _uid, [], _obj getVariable ["tmf_assigngear_role", ""]]];

private _cfg = configFile >> "CfgVehicles" >> _class;
private _faction = faction _obj;
// The map icon: a CfgVehicleIcons class such as iconManMG, and the texture it stands for.
private _icon = getText (_cfg >> "icon");
private _iconPath = getText (configFile >> "CfgVehicleIcons" >> _icon);
if (_iconPath isEqualTo "" && {"\" in _icon}) then { _iconPath = _icon };
private _fields = [
    "id", toJSON _id,
    "kind", toJSON _kind,
    "class", toJSON _class,
    "display", toJSON getText (_cfg >> "displayName"),
    "side", toJSON _side,
    "faction", toJSON _faction,
    "faction_name", toJSON getText (configFile >> "CfgFactionClasses" >> _faction >> "displayName"),
    "icon", toJSON _icon,
    "icon_path", toJSON _iconPath
];
// Variable name given in the editor, the key for matching a unit to its mission slot.
private _var = vehicleVarName _obj;
if (_var isNotEqualTo "") then { _fields append ["var_name", toJSON _var] };
if (_isUnit) then {
    _fields append ["name", toJSON name _obj, "group", toJSON _group, "player", toJSON (_uid isNotEqualTo ""), "uid", toJSON _uid];
    // Slot description from the editor ("Rifleman@Alpha 1-1"), on playable units.
    private _desc = roleDescription _obj;
    if (_desc isNotEqualTo "") then { _fields append ["role_desc", toJSON _desc] };
};
if (aar_tmf) then { _fields append ([_obj, _kind] call aar_fnc_tmfFields) };
["entity", _fields] call aar_fnc_rec;

if (aar_logHits) then {
    // Hit fires only where the object is local, so this covers server AI; players and headless
    // clients report hits on their own objects (aar_fnc_hitClient). Not MPHit: the engine
    // broadcasts that to every machine on every hit.
    _obj addEventHandler ["Hit", { _this call aar_fnc_hit }];
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
