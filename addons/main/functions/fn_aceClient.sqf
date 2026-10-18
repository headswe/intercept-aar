/*
 * ACE events raised only on one machine: wounds (on the machine the wounded unit is local to),
 * medical treatment and dragging or carrying (on the medic's or carrier's machine) and fireteam
 * colours (on the unit's machine). The server runs this code itself and sends it to every other
 * machine (aar_fnc_init), so clients need nothing installed; it must not call any other aar_
 * function, because clients don't have them (the server's own entries go to aar_fnc_aceReport
 * directly). Entries are sent to the server in batches a few times a second.
 *
 * Entries: [kind, actor, ...data, time], see aar_fnc_aceReport; time is CBA_missionTime when it
 * happened, so the server records it at that time. The actor is the unit local to
 * the reporting machine.
 */
if (!isNil "aar_ac_ready" || {isNil "CBA_fnc_addEventHandler"}) exitWith {};
aar_ac_ready = true;
aar_ac_buffer = [];
aar_ac_flushAt = 0;

["ace_medical_woundReceived", {
    params [["_unit", objNull, [objNull]], ["_damages", [], [[]]], ["_shooter", objNull, [objNull]], ["_ammo", "", [""]]];
    if (isNull _unit) exitWith {};
    // Each damage is [damage, body part, real damage].
    private _wounds = [];
    {
        if (_x isEqualType [] && {count _x >= 2}) then {
            _x params [["_damage", 0, [0]], ["_part", "", [""]]];
            if (_damage > 1e-3) then { _wounds pushBack [_part, _damage] };
        };
    } forEach _damages;
    if (_wounds isEqualTo []) exitWith {};
    aar_ac_buffer pushBack ["wound", _unit, _wounds, _shooter, _ammo, CBA_missionTime];
}] call CBA_fnc_addEventHandler;

{
    _x params ["_event", "_result"];
    [_event, compile format ['
        params [["_medic", objNull, [objNull]], ["_patient", objNull, [objNull]], ["_part", "", [""]], ["_action", "", [""]], "", ["_item", "", [""]]];
        if (isNull _medic) exitWith {};
        aar_ac_buffer pushBack ["treatment", _medic, "%1", _patient, _part, _action, _item, CBA_missionTime];
    ', _result]] call CBA_fnc_addEventHandler;
} forEach [["ace_treatmentStarted", "started"], ["ace_treatmentSucceded", "done"], ["ace_treatmentFailed", "failed"]];

{
    _x params ["_event", "_how", "_started"];
    [_event, compile format ['
        params [["_unit", objNull, [objNull]], ["_target", objNull, [objNull]]];
        if (isNull _unit) exitWith {};
        aar_ac_buffer pushBack ["drag", _unit, "%1", %2, _target, CBA_missionTime];
    ', _how, _started]] call CBA_fnc_addEventHandler;
} forEach [
    ["ace_dragging_startedDrag", "drag", true], ["ace_dragging_stoppedDrag", "drag", false],
    ["ace_dragging_startedCarry", "carry", true], ["ace_dragging_stoppedCarry", "carry", false]
];

["ace_interaction_joinedTeam", {
    params [["_unit", objNull, [objNull]], ["_team", "", [""]]];
    if (isNull _unit) exitWith {};
    aar_ac_buffer pushBack ["team", _unit, _team, CBA_missionTime];
}] call CBA_fnc_addEventHandler;

addMissionEventHandler ["EachFrame", {
    if (aar_ac_buffer isEqualTo [] || {diag_tickTime < aar_ac_flushAt}) exitWith {};
    aar_ac_flushAt = diag_tickTime + 0.25;
    private _batch = aar_ac_buffer;
    aar_ac_buffer = [];
    for "_i" from 0 to count _batch - 1 step 200 do {
        if (isServer) then { [_batch select [_i, 200]] call aar_fnc_aceReport } else {
            [_batch select [_i, 200]] remoteExecCall ["aar_fnc_aceReport", 2];
        };
    };
}];
