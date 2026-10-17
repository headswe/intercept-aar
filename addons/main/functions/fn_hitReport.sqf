/*
 * Writes a batch of hits reported by a client (sent by the code in aar_fnc_hitClient): hits on
 * units and vehicles local to that machine, which the server's own Hit handler doesn't see.
 * Hits on an object the sending machine does not own are dropped.
 *
 * Arguments: 0: entries <ARRAY>, see aar_fnc_hitClient
 */
params [["_batch", [], [[]]]];
if (!aar_active || {!aar_logHits}) exitWith {};
private _sender = if (isMultiplayer && {isRemoteExecuted}) then { remoteExecutedOwner } else { -1 };

{
    if !(_x isEqualType []) then { continue };
    _x params [["_unit", objNull, [objNull]], ["_source", objNull, [objNull]], ["_damage", 0, [0]],
        ["_instigator", objNull, [objNull]], ["_age", 0, [0]]];
    if (isNull _unit || {_sender >= 0 && {owner _unit != _sender}}) then { continue };
    [_unit, _source, _damage, _instigator, time - ((_age max 0) min 5)] call aar_fnc_hit;
} forEach (_batch select [0, 500]);
