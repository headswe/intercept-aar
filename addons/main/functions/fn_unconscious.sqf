/*
 * Writes an unconscious or awake record when a unit's state changes. Called from ACE's
 * ace_unconscious event (aar_fnc_init) and from the snapshot, which also catches vanilla
 * incapacitation and anything the event missed. Dying ends unconsciousness without an awake
 * record. An unconscious record names who last hit the unit in the 30 s before (`by`).
 *
 * Arguments: 0: unit <OBJECT>, 1: unconscious <BOOL>
 */
params [["_unit", objNull, [objNull]], ["_state", false, [false]]];
if (!aar_active || {!alive _unit}) exitWith {};
if (_state isEqualTo (_unit getVariable ["aar_uncon", false])) exitWith {};
_unit setVariable ["aar_uncon", _state];
private _id = _unit call aar_fnc_id;
if (_id <= 0) exitWith {};
private _fields = ["unit", toJSON _id, "pos", (getPosASL _unit) call aar_fnc_pos];
if (_state) then {
    (aar_lastHits getOrDefault [_id, []]) params [["_shooter", 0], ["_instigator", 0], "", "", "", ["_t", -1e9]];
    private _by = [_instigator, _shooter] select (_instigator == 0);
    if (_by != 0 && _by != _id && {time - _t <= 30}) then { _fields append ["by", toJSON _by] };
};
[["awake", "unconscious"] select _state, _fields] call aar_fnc_rec;
