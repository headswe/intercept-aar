/*
 * Writes a hit record. Called from the Hit handler added in aar_fnc_register and for hits
 * reported by clients (aar_fnc_hitReport).
 *
 * Arguments: 0: unit <OBJECT>, 1: caused by <OBJECT>, 2: damage <NUMBER>, 3: instigator <OBJECT>,
 *            4: mission time (default: now) <NUMBER>
 */
params ["_unit", "_source", "_damage", "_instigator", ["_time", CBA_missionTime]];
if (!aar_active) exitWith {};
private _target = _unit call aar_fnc_knownId;
private _sourceId = _source call aar_fnc_id;
private _instigatorId = _instigator call aar_fnc_id;
[_target, _sourceId, _instigatorId, "", [], [], _time] call aar_fnc_lastHit;
["hit", [
    "unit", toJSON _target,
    "source", toJSON _sourceId,
    "instigator", toJSON _instigatorId,
    "damage", _damage toFixed 2
], _time] call aar_fnc_rec;
