/*
 * Writes the TMF ORBAT tree (mission attribute TMF_ORBATSettings) as one `orbat` record.
 * Groups and vehicles point into it with their `orbat` field; see aar_fnc_tmfFields.
 *
 * Node in TMF: [id, marker name, icon texture, modifier texture, full name, sort order], [children]
 */
private _raw = getMissionConfigValue ["TMF_ORBATSettings", []];
if (_raw isEqualType "") then { _raw = if (_raw isEqualTo "") then { [] } else { call compile _raw } };
if (isNil "_raw" || {!(_raw isEqualType [])} || {_raw isEqualTo []}) exitWith {};

private _fnc_node = {
    params [["_data", []], ["_children", []]];
    _data params [["_id", -1], ["_name", ""], ["_icon", ""], ["_modifier", ""], ["_fullName", ""], ["_order", 0]];
    createHashMapFromArray [
        ["id", _id],
        ["name", _name],
        ["full_name", _fullName],
        ["icon", _icon],
        ["modifier", _modifier],
        ["order", _order],
        ["children", _children apply { _x call _fnc_node }]
    ]
};

private _teams = [];
{
    _x params ["_condition", ["_root", []]];
    private _team = _root call _fnc_node;
    // TMF keys a tree by side (BI side number, or a side) or by faction class.
    switch (true) do {
        case (_condition isEqualType 0): { _team set ["side", str ([east, west, independent, civilian] param [_condition, sideUnknown])] };
        case (_condition isEqualType west): { _team set ["side", str _condition] };
        default { _team set ["faction", _condition] };
    };
    _teams pushBack _team;
} forEach _raw;

["orbat", ["source", toJSON "tmf", "teams", toJSON _teams]] call aar_fnc_rec;
