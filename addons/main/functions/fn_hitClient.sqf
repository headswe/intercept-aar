/*
 * Client side of the hit recording. The server sends this code to every other machine (players
 * and headless clients, aar_fnc_init), so clients need nothing installed; it must not call any
 * other aar_ function, because clients don't have them.
 *
 * Hit fires only on the machine the hit object is local to, which decides the damage. So every
 * machine adds Hit to every unit and vehicle, and whichever owns it at the time reports the hit
 * to the server (aar_fnc_hitReport) in batches a few times a second. Each entry carries
 * CBA_missionTime when it happened, so the server records it at that time. This replaces MPHit, which
 * the engine broadcasts to every machine on every hit.
 *
 * Entries: [object, source, damage, instigator, CBA_missionTime]
 */
if (isServer || {!isNil "aar_hc_ready"}) exitWith {};
aar_hc_ready = true;
aar_hc_buffer = [];
aar_hc_flushAt = 0;

aar_hc_add = {
    // The flag and the handler both carry over to a respawned unit, so it is added once.
    if (!(_this isKindOf "AllVehicles") || {_this getVariable ["aar_hc", false]}) exitWith {};
    _this setVariable ["aar_hc", true];
    _this addEventHandler ["Hit", {
        params ["_unit", "_source", "_damage", "_instigator"];
        aar_hc_buffer pushBack [_unit, _source, _damage, _instigator, CBA_missionTime];
    }];
};
{ _x call aar_hc_add } forEach (allUnits + vehicles);
addMissionEventHandler ["EntityCreated", { (_this select 0) call aar_hc_add }];

addMissionEventHandler ["EachFrame", {
    if (aar_hc_buffer isEqualTo [] || {diag_tickTime < aar_hc_flushAt}) exitWith {};
    aar_hc_flushAt = diag_tickTime + 0.25;
    private _batch = aar_hc_buffer;
    aar_hc_buffer = [];
    for "_i" from 0 to count _batch - 1 step 200 do {
        [_batch select [_i, 200]] remoteExecCall ["aar_fnc_hitReport", 2];
    };
}];
