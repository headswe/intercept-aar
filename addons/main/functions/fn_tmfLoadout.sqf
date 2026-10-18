/*
 * The unit's TMF assign gear loadout as record fields: faction and role classes and their
 * display names from CfgLoadouts. Empty until TMF has given the unit its gear.
 *
 * Arguments: unit <OBJECT>
 * Returns: [key, json, ...] <ARRAY>
 */
private _role = _this getVariable ["tmf_assigngear_role", ""];
if !(_role isEqualType "" && _role isNotEqualTo "") exitWith { [] };
private _faction = _this getVariable ["tmf_assigngear_faction", ""];
private _factionCfg = missionConfigFile >> "CfgLoadouts" >> _faction;
if (!isClass (_factionCfg >> _role)) then { _factionCfg = configFile >> "CfgLoadouts" >> _faction };
private _cfg = _factionCfg >> _role;
[
    "loadout_faction", toJSON _faction,
    "loadout_faction_name", toJSON getText (_factionCfg >> "displayName"),
    "role", toJSON _role,
    "role_name", toJSON getText (_cfg >> "displayName")
]
