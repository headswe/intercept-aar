/*
 * Advances the snapshot in progress (aar_snap, started by aar_fnc_frame) by up to aar_batch
 * entities, so a large mission spreads the work over several frames instead of one spike.
 * When every entity is done, writes the snap record (timed at the snapshot's start) and the
 * deleted records. Also writes group, side, leader and player changes as it goes.
 *
 * Returns: true when the snapshot is finished <BOOL>
 */
aar_snap params ["_start", "_keyframe", "_ids", "_index", "_rows", "_deleted"];
private _end = (_index + aar_batch) min count _ids;

for "_i" from _index to _end - 1 do {
    private _id = _ids select _i;
    private _entry = aar_entities getOrDefault [_id, []];  // [] once EntityDeleted removed it
    _entry params [["_obj", objNull], "_kind", "_group", "_side", "_uid", "_last"];
    if (_entry isEqualTo []) then { continue };  // already written as deleted
    if (isNull _obj) then {
        _deleted pushBack _id;
    } else {
        private _pos = getPosASL _obj;
        private _dir = getDir _obj;
        private _alive = alive _obj;
        private _damage = damage _obj;
        private _vehicle = 0;
        if (_kind isEqualTo "unit") then {
            private _veh = vehicle _obj;
            // Lookup only: vehicles are registered by the discovery pass in aar_fnc_frame.
            if (_veh != _obj) then { _vehicle = _veh call aar_fnc_knownId };

            // Group, side and player changes are rare, so they are events rather than snapshot columns.
            if (_alive) then {
                // Unconscious (ACE) or incapacitated (vanilla); ACE's event usually gets there first.
                private _uncon = lifeState _obj == "INCAPACITATED" || {_obj getVariable ["ACE_isUnconscious", false]};
                if (_uncon isNotEqualTo (_obj getVariable ["aar_uncon", false])) then { [_obj, _uncon] call aar_fnc_unconscious };
                if (aar_logAI) then {
                    private _grp = group _obj;
                    if (local _grp && {!(_grp getVariable ["aar_group", false])}) then { _grp call aar_fnc_registerGroup };
                };
                private _newGroup = if (isNull group _obj) then { "" } else { groupId group _obj };
                private _newSide = str side _obj;
                if (_newGroup isNotEqualTo _group || _newSide isNotEqualTo _side) then {
                    _entry set [2, _newGroup];
                    _entry set [3, _newSide];
                    private _fields = ["unit", toJSON _id, "group", toJSON _newGroup, "side", toJSON _newSide];
                    if (aar_tmf) then { _fields append (_obj call aar_fnc_tmfGroupFields) };
                    ["group", _fields] call aar_fnc_rec;
                };
                // Group markers sit on the leader, as TMF draws them.
                if (!isNull group _obj && {leader group _obj isEqualTo _obj}) then {
                    private _key = _newSide + "|" + _newGroup;
                    if (aar_leaders getOrDefault [_key, -1] isNotEqualTo _id) then {
                        aar_leaders set [_key, _id];
                        ["leader", ["unit", toJSON _id, "group", toJSON _newGroup, "side", toJSON _newSide]] call aar_fnc_rec;
                    };
                };
                if (aar_tmf) then {
                    // TMF gives players their gear after the unit is first seen, and respawns can change it.
                    private _role = _obj getVariable ["tmf_assigngear_role", ""];
                    if (_role isNotEqualTo (_entry select 6)) then {
                        _entry set [6, _role];
                        ["loadout", ["unit", toJSON _id] + (_obj call aar_fnc_tmfLoadout)] call aar_fnc_rec;
                    };
                };
                private _newUid = if (isPlayer _obj) then { getPlayerUID _obj } else { "" };
                if (_newUid isNotEqualTo _uid) then {
                    _entry set [4, _newUid];
                    ["player", ["unit", toJSON _id, "uid", toJSON _newUid, "name", toJSON name _obj]] call aar_fnc_rec;
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
            _entry set [5, [_pos select 0, _pos select 1, _pos select 2, _dir, _alive, _damage, _vehicle]];
            // [id, x, y, z, dir, alive, damage, vehicle_id]
            _rows pushBack format ["[%1,%2,%3,%4,%5,%6,%7,%8]",
                _id,
                (_pos select 0) toFixed 2, (_pos select 1) toFixed 2, (_pos select 2) toFixed 2,
                (round _dir) mod 360,
                [0, 1] select _alive,
                _damage toFixed 2,
                _vehicle
            ];
        };
    };
};
aar_snap set [3, _end];
if (_end < count _ids) exitWith {false};

["snap", ["key", toJSON _keyframe, "e", "[" + (_rows joinString ",") + "]"], _start] call aar_fnc_rec;
{
    ["deleted", ["id", toJSON _x]] call aar_fnc_rec;
    aar_entities deleteAt _x;
} forEach _deleted;
true
