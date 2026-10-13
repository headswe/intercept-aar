/*
 * TMF fields for an entity record: where it sits in the ORBAT and, for units, the TMF loadout.
 *
 * Arguments: 0: object <OBJECT>, 1: kind <STRING>
 * Returns: [key, json, ...] <ARRAY>
 */
params ["_obj", "_kind"];
private _fields = [];
if (_kind isEqualTo "unit") then {
    // Units sit under their group's node; TMF falls back to the team's root node when it is unset.
    private _parent = (group _obj) getVariable ["TMF_OrbatParent", -1];
    if (_parent isNotEqualTo -1) then { _fields append ["orbat", toJSON _parent] };
    _fields append (_obj call aar_fnc_tmfLoadout);
} else {
    private _parent = _obj getVariable ["TMF_OrbatParent", -1];
    if (_parent isNotEqualTo -1) then { _fields append ["orbat", toJSON _parent] };
    private _callsign = _obj getVariable ["TMF_orbat_vehicleCallsign", ""];
    if (_callsign isEqualType "" && _callsign isNotEqualTo "") then { _fields append ["callsign", toJSON _callsign] };
    private _team = _obj getVariable ["TMF_orbat_team", ""];
    if (_team isEqualType []) then { _team = _team param [0, ""] };
    if (_team isEqualType "" && _team isNotEqualTo "") then { _fields append ["orbat_team", toJSON _team] };
};
_fields
