/*
 * Writes a batch of ACE events reported by a machine (sent by the code in aar_fnc_aceClient,
 * which the server runs too). Entries whose actor the sending machine does not own are dropped.
 *
 *   ["wound", unit, [[body part, damage], ...], shooter, ammo or cause, age]
 *   ["treatment", medic, "started" | "done" | "failed", patient, body part, action class, item used, age]
 *   ["drag", unit, "drag" | "carry", started <BOOL>, target, age]
 *   ["team", unit, colour, age]
 *
 * Arguments: 0: entries <ARRAY>
 */
params [["_batch", [], [[]]]];
if (!aar_active || {!aar_logACE}) exitWith {};
private _sender = if (isMultiplayer && {isRemoteExecuted}) then { remoteExecutedOwner } else { -1 };

{
    if !(_x isEqualType [] && {count _x >= 3}) then { continue };
    _x params [["_kind", "", [""]], ["_actor", objNull, [objNull]]];
    if (isNull _actor || {_sender >= 0 && {owner _actor != _sender}}) then { continue };
    private _age = _x select -1;
    private _time = time - ((([_age, 0] select !(_age isEqualType 0)) max 0) min 5);
    switch (_kind) do {
        case "wound": {
            _x params ["", "", ["_wounds", [], [[]]], ["_shooter", objNull, [objNull]], ["_cause", "", [""]]];
            private _clean = [];
            {
                if (_x isEqualTypeArray ["", 0]) then { _clean pushBack [_x select 0, (round ((_x select 1) * 1000)) / 1000] };
            } forEach (_wounds select [0, 20]);
            if (_clean isEqualTo []) exitWith {};
            private _fields = ["unit", toJSON (_actor call aar_fnc_id), "wounds", toJSON _clean, "cause", toJSON _cause, "pos", (getPosASL _actor) call aar_fnc_pos];
            private _by = _shooter call aar_fnc_id;
            if (_by != 0) then { _fields append ["by", toJSON _by] };
            ["wound", _fields, _time] call aar_fnc_rec;
        };
        case "treatment": {
            _x params ["", "", ["_result", "", [""]], ["_patient", objNull, [objNull]], ["_part", "", [""]], ["_action", "", [""]], ["_item", "", [""]]];
            if !(_result in ["started", "done", "failed"]) exitWith {};
            private _fields = ["medic", toJSON (_actor call aar_fnc_id), "patient", toJSON (_patient call aar_fnc_id),
                "result", toJSON _result, "part", toJSON _part, "action", toJSON _action];
            if (_item isNotEqualTo "") then { _fields append ["item", toJSON _item] };
            ["treatment", _fields, _time] call aar_fnc_rec;
        };
        case "drag": {
            _x params ["", "", ["_how", "", [""]], ["_started", false, [false]], ["_target", objNull, [objNull]]];
            if !(_how in ["drag", "carry"]) exitWith {};
            ["drag", ["unit", toJSON (_actor call aar_fnc_id), "target", toJSON (_target call aar_fnc_id),
                "how", toJSON _how, "started", toJSON _started, "pos", (getPosASL _actor) call aar_fnc_pos], _time] call aar_fnc_rec;
        };
        case "team": {
            _x params ["", "", ["_team", "", [""]]];
            ["team", ["unit", toJSON (_actor call aar_fnc_id), "team", toJSON _team], _time] call aar_fnc_rec;
        };
    };
} forEach (_batch select [0, 500]);
