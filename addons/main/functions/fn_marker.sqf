/*
 * Writes a marker report from a client (sent by the code in aar_fnc_markerClient): a marker the
 * server does not have because it was drawn on a channel other than Global.
 *   "created" / "updated": the marker's whole state, see aar_fnc_markerClient
 *   "deleted": the state just before it was deleted
 * A report about a marker the server knows itself is dropped, since the server's own marker
 * event handlers record it.
 *
 * Arguments: 0: kind <STRING>, 1: state <ARRAY>, 2: CBA_missionTime on the client when it happened <NUMBER>
 */
params [["_kind", "", [""]], ["_state", [], [[]]], ["_time", CBA_missionTime, [0]]];
if (!aar_active || {!aar_logMarkers} || {!(_kind in ["created", "updated", "deleted"])}) exitWith {};
_state params [["_marker", "", [""]], ["_text", "", [""]], ["_type", "", [""]], ["_color", "", [""]], ["_shape", "", [""]],
    ["_brush", "", [""]], ["_size", [1, 1], [[]]], ["_dir", 0, [0]], ["_alpha", 1, [0]], ["_pos", [0, 0, 0], [[]]],
    ["_line", [], [[]]], ["_channel", -1, [0]]];
if (_marker isEqualTo "" || {count _marker > 128} || {markerType _marker isNotEqualTo ""}) exitWith {};
_time = _time call aar_fnc_reportTime;

// The player on the machine that sent it.
private _by = objNull;
if (isMultiplayer && {isRemoteExecuted}) then {
    private _i = allPlayers findIf { owner _x == remoteExecutedOwner };
    if (_i >= 0) then { _by = allPlayers select _i };
};

if (_kind == "deleted") exitWith {
    private _fields = ["marker", toJSON _marker];
    if (!isNull _by) then { _fields append ["by", toJSON (_by call aar_fnc_id)] };
    ["marker_deleted", _fields, _time] call aar_fnc_rec;
};

private _num = { params ["_v", "_digits"]; if (_v isEqualType 0) then { _v toFixed _digits } else { "0" } };
private _fields = [
    "marker", toJSON _marker,
    "text", toJSON (_text select [0, 256]),
    "markerType", toJSON (_type select [0, 64]),
    "color", toJSON (_color select [0, 64]),
    "shape", toJSON (_shape select [0, 16]),
    "brush", toJSON (_brush select [0, 64]),
    "size", "[" + ([_size param [0, 1], 2] call _num) + "," + ([_size param [1, 1], 2] call _num) + "]",
    "dir", _dir toFixed 1,
    "alpha", _alpha toFixed 2,
    "pos", ((_pos select [0, 3]) apply { [0, _x] select (_x isEqualType 0) }) call aar_fnc_pos
];
if (_shape == "POLYLINE") then {
    _fields append ["line", "[" + (((_line select [0, 2000]) select { _x isEqualType 0 }) apply { _x toFixed 1 } joinString ",") + "]"];
};
if (_kind == "created") then {
    _fields append ["channel", toJSON _channel];
    if (!isNull _by) then { _fields append ["owner", toJSON (_by call aar_fnc_id)] };
};
[["marker_updated", "marker_created"] select (_kind == "created"), _fields, _time] call aar_fnc_rec;
