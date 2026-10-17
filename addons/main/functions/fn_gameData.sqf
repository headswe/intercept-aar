/*
 * Exports display names and map icons for the viewer, once per game version and mod list, so
 * recordings only need class names. Sends the config's names to the extension, which writes
 * aar-cfg.json and finds the map icon textures in the server's PBOs for aar-icons.json, next to
 * the recordings (see src/gamedata.hpp). Spawned, so the work spreads over frames; does nothing
 * when the files already match.
 *
 * Arguments: none
 */
private _mods = getLoadedModsInfo;
// [name, folder, default, official, origin, hash, short hash, workshop id]
private _key = ((productVersion select [2, 2]) joinString ".") + "|" + ((_mods apply { (_x select 1) + ":" + (_x select 6) }) joinString ";");
private _check = ("arma_aar" callExtension ["gd_check", [_key]]) select 0;
if (_check isNotEqualTo "0") exitWith {};  // "1" up to date, "busy", or "" when the extension did not load
diag_log "[AAR] exporting names and map icons for the viewer";

// Rows go over in batches; each batch is one JSON object.
private _rows = createHashMap;
private _flush = {
    params ["_table"];
    if (count _rows > 0) then { "arma_aar" callExtension ["gd_add", [_table, toJSON _rows]] };
    _rows = createHashMap;
};

{
    private _name = getText (_x >> "displayName");
    if (_name isNotEqualTo "") then {
        _rows set [configName _x, [_name, getText (_x >> "picture"), getText (_x >> "icon"), getText (_x >> "faction")]];
        if (count _rows >= 200) then { ["vehicles"] call _flush };
    };
} forEach ("getNumber (_x >> 'scope') >= 1" configClasses (configFile >> "CfgVehicles"));
["vehicles"] call _flush;

{
    private _name = getText (_x >> "displayName");
    if (_name isNotEqualTo "") then {
        _rows set [configName _x, [_name, getText (_x >> "picture")]];
        if (count _rows >= 200) then { ["weapons"] call _flush };
    };
} forEach ("getNumber (_x >> 'scope') >= 1" configClasses (configFile >> "CfgWeapons"));
["weapons"] call _flush;

{ _rows set [configName _x, [getText (_x >> "displayName"), getText (_x >> "flag")]] } forEach ("true" configClasses (configFile >> "CfgFactionClasses"));
["factions"] call _flush;

private _textures = [];
{
    if (isText _x) then { _rows set [configName _x, getText _x]; _textures pushBackUnique getText _x };
} forEach configProperties [configFile >> "CfgVehicleIcons", "true", true];
["vehicle_icons"] call _flush;

private _header = createHashMap;
_header set ["game", (productVersion select [2, 2]) joinString "."];
_header set ["mods", (_mods select { !(_x select 2) }) apply { _x select 0 }];
"arma_aar" callExtension ["gd_done", [toJSON _header, toJSON _textures, toJSON (_mods apply { _x select 1 })]];

private _status = "busy";
private _until = diag_tickTime + 600;
while { _status isEqualTo "busy" && diag_tickTime < _until } do {
    sleep 2;
    _status = "arma_aar" callExtension "gd_status";
};
diag_log format ["[AAR] names and map icons for the viewer: %1", _status];
