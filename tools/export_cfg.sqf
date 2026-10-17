/*
 * Exports display names and texture paths from the loaded game config for the AAR viewer, so the
 * recordings only need class names. Run it with the same mods as the server, e.g. in the editor's
 * debug console (paste and press Local Exec), then paste the clipboard into a file named aar-cfg.json.
 * tools/export_icons.py turns the textures it names into images.
 *
 *   vehicles:      class -> [display name, picture, map icon class, faction]
 *   weapons:       class -> [display name, picture]
 *   factions:      class -> [display name, flag]
 *   vehicle_icons: CfgVehicleIcons class -> texture
 */
private _out = createHashMap;
_out set ["format", "aar-cfg"];
_out set ["version", 1];
_out set ["game", productVersion select 2];
_out set ["mods", (getLoadedModsInfo select {!(_x select 2)}) apply {_x select 0}];

private _vehicles = createHashMap;
{
    private _name = getText (_x >> "displayName");
    if (_name isNotEqualTo "") then {
        _vehicles set [configName _x, [_name, getText (_x >> "picture"), getText (_x >> "icon"), getText (_x >> "faction")]];
    };
} forEach ("getNumber (_x >> 'scope') >= 1" configClasses (configFile >> "CfgVehicles"));
_out set ["vehicles", _vehicles];

private _weapons = createHashMap;
{
    private _name = getText (_x >> "displayName");
    if (_name isNotEqualTo "") then { _weapons set [configName _x, [_name, getText (_x >> "picture")]] };
} forEach ("getNumber (_x >> 'scope') >= 1" configClasses (configFile >> "CfgWeapons"));
_out set ["weapons", _weapons];

private _factions = createHashMap;
{
    _factions set [configName _x, [getText (_x >> "displayName"), getText (_x >> "flag")]];
} forEach ("true" configClasses (configFile >> "CfgFactionClasses"));
_out set ["factions", _factions];

private _icons = createHashMap;
{
    if (isText _x) then { _icons set [configName _x, getText _x] };
} forEach configProperties [configFile >> "CfgVehicleIcons", "true", true];
_out set ["vehicle_icons", _icons];

private _json = toJSON _out;
copyToClipboard _json;
hint format ["AAR config copied: %1 vehicles, %2 weapons, %3 KB. Paste it into aar-cfg.json.",
    count _vehicles, count _weapons, round (count _json / 1024)];
