/*
 * TMF fields that follow a unit's group: the ORBAT node the group sits under, the group's short
 * name (the text on its TMF group marker, e.g. "A1"), and with TMF's ACRE2 radio networks the
 * network the unit is on and the channels TMF puts it on (indexes into that network's channels
 * in the radio_nets record).
 *
 * Arguments: unit <OBJECT>
 * Returns: [key, json, ...] <ARRAY>
 */
private _group = group _this;
private _fields = [];
// Units sit under their group's node; TMF falls back to the team's root node when it is unset.
private _parent = _group getVariable ["TMF_OrbatParent", -1];
if (_parent isNotEqualTo -1) then { _fields append ["orbat", toJSON _parent] };

// TMF_groupMarker: [icon texture, marker text, size texture], sometimes saved as a string.
private _marker = _group getVariable ["TMF_groupMarker", []];
if (_marker isEqualType "") then { _marker = if (_marker isEqualTo "") then { [] } else { parseSimpleArray _marker } };
if (_marker isEqualType []) then {
    private _short = _marker param [1, ""];
    if (_short isEqualType "" && {_short isNotEqualTo ""}) then { _fields append ["group_short", toJSON _short] };
};

if (aar_tmfNets isNotEqualTo [] && {!isNil "TMF_acre2_fnc_unitToPreset"}) then {
    private _net = [_this] call TMF_acre2_fnc_unitToPreset;
    if (_net < 0) exitWith {};
    _fields append ["radio_net", toJSON _net];
    // Same rules as TMF's client init: the channel's conditions, or the channel listed on the
    // unit, its group, or (for the leader) the group's leader list.
    private _list = {
        params ["_entity", "_var"];
        private _value = _entity getVariable [_var, []];
        if (_value isEqualType "") then { _value = if (_value isEqualTo "") then { [] } else { parseSimpleArray _value } };
        [[], _value] select (_value isEqualType [])
    };
    private _assigned = ([_this, "TMF_Channellist"] call _list) + ([_group, "TMF_Channellist"] call _list);
    if (leader _group == _this) then { _assigned append ([_group, "TMF_ChannellistLeader"] call _list) };
    private _channels = [];
    {
        private _conditions = _x param [3, []];
        if (_forEachIndex in _assigned || {[_this, _conditions] call TMF_common_fnc_evaluateCondArray}) then { _channels pushBack _forEachIndex };
    } forEach ((aar_tmfNets select _net) param [1, []]);
    _fields append ["radio_channels", toJSON _channels];
};
_fields
