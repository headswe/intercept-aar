/*
 * AAR id of an object without registering it. 0 for null, unknown or ignored objects.
 *
 * Arguments: object <OBJECT>
 */
params [["_obj", objNull]];
if (isNull _obj) exitWith {0};
(_obj getVariable ["aar_id", 0]) max 0
