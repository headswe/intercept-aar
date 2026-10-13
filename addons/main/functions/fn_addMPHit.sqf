/*
 * Adds the MPHit handler to an object that is no longer local to the server. MPHit runs on
 * every machine and its code is sent with each hit, so it stays one line and does nothing on
 * clients (they don't have this mod).
 *
 * Arguments: 0: object <OBJECT>
 */
params ["_obj"];
if (_obj getVariable ["aar_mpHit", false]) exitWith {};
_obj setVariable ["aar_mpHit", true];
_obj addMPEventHandler ["MPHit", { if (isServer) then { _this call aar_fnc_hit } }];
