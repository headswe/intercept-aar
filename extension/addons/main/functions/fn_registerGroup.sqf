/*
 * Adds the AI awareness handlers to a group and writes its current behaviour, so the
 * replay starts from a known state. Groups fire these where they are local, so this covers
 * AI groups run by the server, not groups led by a player or run by a headless client.
 *
 * Arguments: 0: group <GROUP>
 */
params ["_group"];
if (isNull _group || {isNull leader _group} || {_group getVariable ["aar_group", false]}) exitWith {};
_group setVariable ["aar_group", true];

private _fields = [_group] call aar_fnc_groupFields;
_fields append ["mode", toJSON behaviour leader _group];
["combat_mode", _fields] call aar_fnc_rec;

_group addEventHandler ["CombatModeChanged", {
    params ["_group", "_newMode"];
    if (!aar_active) exitWith {};
    private _fields = [_group] call aar_fnc_groupFields;
    _fields append ["mode", toJSON _newMode];
    ["combat_mode", _fields] call aar_fnc_rec;
}];

_group addEventHandler ["EnemyDetected", {
    params ["_group", "_newTarget"];
    if (!aar_active) exitWith {};
    private _fields = [_group] call aar_fnc_groupFields;
    _fields append ["target", toJSON (_newTarget call aar_fnc_id)];
    ["enemy_detected", _fields] call aar_fnc_rec;
}];

_group addEventHandler ["Fleeing", {
    params ["_group", "_fleeingNow"];
    if (!aar_active) exitWith {};
    private _fields = [_group] call aar_fnc_groupFields;
    _fields append ["fleeing", toJSON _fleeingNow];
    ["fleeing", _fields] call aar_fnc_rec;
}];
