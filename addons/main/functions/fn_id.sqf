/*
 * AAR id of an object, registering it if it is new. 0 for null or ignored objects.
 *
 * Arguments: object <OBJECT>
 */
params [["_obj", objNull]];
if (isNull _obj) exitWith {0};
private _id = _obj getVariable ["aar_id", 0];
if (_id < 0) exitWith {0};
if (_id > 0) exitWith {_id};
_obj call aar_fnc_register
