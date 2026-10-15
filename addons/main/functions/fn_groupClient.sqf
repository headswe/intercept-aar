/*
 * Client side of the AI group recording. The server sends this code to every other machine
 * (players and headless clients, aar_fnc_init), so clients need nothing installed; it must not
 * call any other aar_ function, because clients don't have them.
 *
 * A group's behaviour, detection and fleeing events fire only on the machine the group is local
 * to: the leading player's, or the headless client running it. So every few seconds this adds
 * the handlers to the groups local here, and they report to the server (aar_fnc_groupEvent),
 * starting with the group's current behaviour.
 */
if (isServer || {!isNil "aar_gc_ready"}) exitWith {};
aar_gc_ready = true;
aar_gc_send = { _this remoteExecCall ["aar_fnc_groupEvent", 2] };
aar_gc_scanAt = 0;

addMissionEventHandler ["EachFrame", {
    if (diag_tickTime < aar_gc_scanAt) exitWith {};
    aar_gc_scanAt = diag_tickTime + 5;
    {
        if (local _x && {!isNull leader _x} && {!(_x getVariable ["aar_gc", false])}) then {
            _x setVariable ["aar_gc", true];
            ["combat_mode", _x, behaviour leader _x] call aar_gc_send;
            _x addEventHandler ["CombatModeChanged", {
                params ["_group", "_newMode"];
                ["combat_mode", _group, _newMode] call aar_gc_send;
            }];
            _x addEventHandler ["EnemyDetected", {
                params ["_group", "_newTarget"];
                ["enemy_detected", _group, _newTarget] call aar_gc_send;
            }];
            _x addEventHandler ["Fleeing", {
                params ["_group", "_fleeingNow"];
                ["fleeing", _group, _fleeingNow] call aar_gc_send;
            }];
        };
    } forEach allGroups;
}];
