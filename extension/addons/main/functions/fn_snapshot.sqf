/*
 * Registers new units and vehicles, then writes a snapshot of every entity that changed
 * (or of all of them on a keyframe). Also writes group, side and player changes.
 *
 * Arguments: 0: keyframe <BOOL>
 */
params ["_keyframe"];

{ _x call aar_fnc_id } forEach allUnits;
{ _x call aar_fnc_id } forEach vehicles;

private _rows = [];
private _deleted = [];
{
    _y params ["_obj", "_kind", "_group", "_side", "_uid", "_last"];
    if (isNull _obj) then {
        _deleted pushBack _x;
    } else {
        private _pos = getPosASL _obj;
        private _dir = getDir _obj;
        private _alive = alive _obj;
        private _damage = damage _obj;
        private _vehicle = 0;
        if (_kind isEqualTo "unit") then {
            private _veh = vehicle _obj;
            // Lookup only: registering here would change aar_entities while we iterate it.
            if (_veh != _obj) then { _vehicle = _veh call aar_fnc_knownId };

            // Group, side and player changes are rare, so they are events rather than snapshot columns.
            if (_alive) then {
                private _newGroup = if (isNull group _obj) then { "" } else { groupId group _obj };
                private _newSide = str side _obj;
                if (_newGroup isNotEqualTo _group || _newSide isNotEqualTo _side) then {
                    _y set [2, _newGroup];
                    _y set [3, _newSide];
                    ["group", ["unit", str _x, "group", str _newGroup, "side", str _newSide]] call aar_fnc_rec;
                };
                private _newUid = if (isPlayer _obj) then { getPlayerUID _obj } else { "" };
                if (_newUid isNotEqualTo _uid) then {
                    _y set [4, _newUid];
                    ["player", ["unit", str _x, "uid", str _newUid, "name", str name _obj]] call aar_fnc_rec;
                };
            };
        };

        private _changed = _keyframe || {_last isEqualTo []} || {
            _last params ["_lx", "_ly", "_lz", "_ldir", "_lalive", "_ldamage", "_lvehicle"];
            _alive isNotEqualTo _lalive || _vehicle != _lvehicle
                || {abs ((_pos select 0) - _lx) > 0.1} || {abs ((_pos select 1) - _ly) > 0.1} || {abs ((_pos select 2) - _lz) > 0.1}
                || {abs (_dir - _ldir) > 1} || {abs (_damage - _ldamage) > 0.01}
        };
        if (_changed) then {
            _y set [5, [_pos select 0, _pos select 1, _pos select 2, _dir, _alive, _damage, _vehicle]];
            // [id, x, y, z, dir, alive, damage, vehicle_id]
            _rows pushBack format ["[%1,%2,%3,%4,%5,%6,%7,%8]",
                _x,
                (_pos select 0) toFixed 2, (_pos select 1) toFixed 2, (_pos select 2) toFixed 2,
                (round _dir) mod 360,
                [0, 1] select _alive,
                _damage toFixed 2,
                _vehicle
            ];
        };
    };
} forEach aar_entities;

["snap", ["key", str _keyframe, "e", "[" + (_rows joinString ",") + "]"]] call aar_fnc_rec;

{
    ["deleted", ["id", str _x]] call aar_fnc_rec;
    aar_entities deleteAt _x;
} forEach _deleted;
