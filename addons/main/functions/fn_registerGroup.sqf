/*
 * Adds the AI awareness handlers to a group and writes its current behaviour, so the
 * replay starts from a known state. Groups fire these where they are local, so this covers
 * groups run by the server; groups led by a player or run by a headless client are reported
 * by that machine (aar_fnc_groupClient).
 *
 * Arguments: 0: group <GROUP>
 */
params ["_group"];
if (isNull _group || {isNull leader _group} || {_group getVariable ["aar_group", false]}) exitWith {};
_group setVariable ["aar_group", true];

["combat_mode", _group, behaviour leader _group] call aar_fnc_groupEvent;

_group addEventHandler ["CombatModeChanged", {
    params ["_group", "_newMode"];
    ["combat_mode", _group, _newMode] call aar_fnc_groupEvent;
}];
_group addEventHandler ["EnemyDetected", {
    params ["_group", "_newTarget"];
    ["enemy_detected", _group, _newTarget] call aar_fnc_groupEvent;
}];
_group addEventHandler ["Fleeing", {
    params ["_group", "_fleeingNow"];
    ["fleeing", _group, _fleeingNow] call aar_fnc_groupEvent;
}];
