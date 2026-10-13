/*
 * Writes the end record and closes the file. Event handlers stay but do nothing afterwards.
 *
 * Arguments: 0: reason <STRING>
 */
params [["_reason", "stopped"]];
if (!aar_active) exitWith {};

["end", ["reason", toJSON _reason, "entities", toJSON (aar_nextId - 1), "projectiles", toJSON (aar_nextPid - 1)]] call aar_fnc_rec;
[] call aar_fnc_flush;
aar_active = false;
"arma_aar" callExtension ["close", []];
diag_log format ["[AAR] stopped (%1), wrote %2", _reason, aar_path];
