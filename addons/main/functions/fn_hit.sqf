/*
 * Writes a hit record. Called from the Hit and MPHit handlers added in aar_fnc_register.
 *
 * Arguments: 0: unit <OBJECT>, 1: caused by <OBJECT>, 2: damage <NUMBER>, 3: instigator <OBJECT>
 */
params ["_unit", "_source", "_damage", "_instigator"];
if (!aar_active) exitWith {};
["hit", [
    "unit", toJSON (_unit call aar_fnc_knownId),
    "source", toJSON (_source call aar_fnc_id),
    "instigator", toJSON (_instigator call aar_fnc_id),
    "damage", _damage toFixed 2
]] call aar_fnc_rec;
