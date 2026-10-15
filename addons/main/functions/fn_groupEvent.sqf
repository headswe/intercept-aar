/*
 * Writes an AI group event, from the server's own group event handlers (aar_fnc_registerGroup)
 * or reported by the machine the group is local to (aar_fnc_groupClient). A report about a group
 * the sending machine does not own is dropped.
 *   "combat_mode": value is the behaviour (SAFE, AWARE, ...); written only when it changed
 *   "enemy_detected": value is the target; the same target is written at most once per
 *       enemyDetectedCooldown, since the engine re-fires this each time the group re-acquires
 *       a target it lost sight of
 *   "fleeing": value is whether the group is fleeing now
 *
 * Arguments: 0: kind <STRING>, 1: group <GROUP>, 2: value
 */
params [["_kind", "", [""]], ["_group", grpNull, [grpNull]], ["_value", nil, ["", objNull, false]]];
if (!aar_active || {!aar_logAI} || {isNull _group} || {isNil "_value"}) exitWith {};
if (isMultiplayer && {isRemoteExecuted} && {groupOwner _group != remoteExecutedOwner}) exitWith {};

switch (_kind) do {
    case "combat_mode": {
        if !(_value isEqualType "") exitWith {};
        if ((_group getVariable ["aar_mode", ""]) isEqualTo _value) exitWith {};
        _group setVariable ["aar_mode", _value];
        ["combat_mode", ([_group] call aar_fnc_groupFields) + ["mode", toJSON (_value select [0, 16])]] call aar_fnc_rec;
    };
    case "enemy_detected": {
        if !(_value isEqualType objNull) exitWith {};
        private _target = _value call aar_fnc_id;
        private _seen = _group getVariable "aar_detected";
        if (isNil "_seen") then { _seen = createHashMap; _group setVariable ["aar_detected", _seen] };
        if (time < (_seen getOrDefault [_target, -1e9]) + aar_enemyDetectedCooldown) exitWith {};
        _seen set [_target, time];
        ["enemy_detected", ([_group] call aar_fnc_groupFields) + ["target", toJSON _target]] call aar_fnc_rec;
    };
    case "fleeing": {
        if !(_value isEqualType false) exitWith {};
        ["fleeing", ([_group] call aar_fnc_groupFields) + ["fleeing", toJSON _value]] call aar_fnc_rec;
    };
};
