/*
 * Writes a hit record. Called from the Hit handler added in aar_fnc_register and for hits
 * reported by clients (aar_fnc_hitReport).
 *
 * Arguments: 0: unit <OBJECT>, 1: caused by <OBJECT>, 2: damage <NUMBER>, 3: instigator <OBJECT>,
 *            4: mission time (default: now) <NUMBER>
 */
params ["_unit", "_source", "_damage", "_instigator", ["_time", time]];
if (!aar_active) exitWith {};
["hit", [
    "unit", toJSON (_unit call aar_fnc_knownId),
    "source", toJSON (_source call aar_fnc_id),
    "instigator", toJSON (_instigator call aar_fnc_id),
    "damage", _damage toFixed 2
], _time] call aar_fnc_rec;
