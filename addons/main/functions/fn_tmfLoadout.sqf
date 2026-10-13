/*
 * The unit's TMF assign gear loadout as record fields: faction and role class, and the role's
 * display name from CfgLoadouts. Empty until TMF has given the unit its gear.
 *
 * Arguments: unit <OBJECT>
 * Returns: [key, json, ...] <ARRAY>
 */
private _role = _this getVariable ["tmf_assigngear_role", ""];
if !(_role isEqualType "" && _role isNotEqualTo "") exitWith { [] };
private _faction = _this getVariable ["tmf_assigngear_faction", ""];
private _cfg = missionConfigFile >> "CfgLoadouts" >> _faction >> _role;
if (!isClass _cfg) then { _cfg = configFile >> "CfgLoadouts" >> _faction >> _role };
["loadout_faction", toJSON _faction, "role", toJSON _role, "role_name", toJSON getText (_cfg >> "displayName")]
