/*
 * Exports display names and textures for the viewer, so recordings only need class names. Not run
 * by itself: call it on the server when the mods change, e.g. from the debug console with
 * Server Exec:
 *
 *   [] spawn aar_fnc_gameData
 *   [["F:/ArmaMods", "G:/Workshop/content/107410"]] spawn aar_fnc_gameData
 *
 * Sends the config's names to the extension, which writes aar-cfg.json next to the recordings,
 * then finds every map icon, vehicle and weapon picture and faction flag in the PBOs of the game
 * and the loaded mods and writes each as a PNG under icons/, listed in aar-icons.json
 * (see src/gamedata.hpp). Must be spawned: it sleeps while the extension works and logs the
 * result to the RPT.
 *
 * Optional argument: array of extra folders to search for mod PBOs.
 */
params [["_extraPaths", [], [[]]]];
if (!canSuspend) exitWith { [_extraPaths] spawn aar_fnc_gameData };
private _begin = ("arma_aar" callExtension ["gd_begin", []]) select 0;
if (_begin isNotEqualTo "ok") exitWith {
    diag_log format ["[AAR] game data export not started: %1", ["the extension did not load", "one is already running"] select (_begin isEqualTo "busy")];
};
diag_log "[AAR] exporting names and textures for the viewer";

// Rows go over in batches; each batch is one JSON object.
private _rows = createHashMap;
private _textures = createHashMap;
private _flush = {
    params ["_table"];
    if (count _rows > 0) then { "arma_aar" callExtension ["gd_add", [_table, toJSON _rows]] };
    _rows = createHashMap;
};
private _texture = { if (_this isNotEqualTo "") then { _textures set [toLowerANSI _this, _this] } };

{
    private _name = getText (_x >> "displayName");
    if (_name isNotEqualTo "") then {
        private _picture = getText (_x >> "picture");
        private _icon = getText (_x >> "icon");
        _picture call _texture;
        if ("\" in _icon) then { _icon call _texture };
        _rows set [configName _x, [_name, _picture, _icon, getText (_x >> "faction")]];
        if (count _rows >= 200) then { ["vehicles"] call _flush };
    };
} forEach ("getNumber (_x >> 'scope') >= 1" configClasses (configFile >> "CfgVehicles"));
["vehicles"] call _flush;

{
    private _name = getText (_x >> "displayName");
    if (_name isNotEqualTo "") then {
        private _picture = getText (_x >> "picture");
        _picture call _texture;
        _rows set [configName _x, [_name, _picture]];
        if (count _rows >= 200) then { ["weapons"] call _flush };
    };
} forEach ("getNumber (_x >> 'scope') >= 1" configClasses (configFile >> "CfgWeapons"));
["weapons"] call _flush;

{
    private _flag = getText (_x >> "flag");
    _flag call _texture;
    _rows set [configName _x, [getText (_x >> "displayName"), _flag]];
} forEach ("true" configClasses (configFile >> "CfgFactionClasses"));
["factions"] call _flush;

{
    if (isText _x) then {
        _rows set [configName _x, getText _x];
        (getText _x) call _texture;
        if (count _rows >= 200) then { ["vehicle_icons"] call _flush };
    };
} forEach configProperties [configFile >> "CfgVehicleIcons", "true", true];
["vehicle_icons"] call _flush;

{
    private _icon = getText (_x >> "icon");
    if (_icon isNotEqualTo "") then {
        _rows set [configName _x, _icon];
        _icon call _texture;
        if (count _rows >= 200) then { ["marker_icons"] call _flush };
    };
} forEach configProperties [configFile >> "CfgMarkers", "true", true];
["marker_icons"] call _flush;

{
    private _color = getArray (_x >> "color");
    if (count _color >= 3) then {
        _color = _color apply { if (_x isEqualType "") then { call compile _x } else { _x } };
        _rows set [configName _x, [_color, getNumber (_x >> "showEditorMarkerColor") > 0]];
        if (count _rows >= 200) then { ["marker_defaults"] call _flush };
    };
} forEach configProperties [configFile >> "CfgMarkers", "true", true];
["marker_defaults"] call _flush;

{
    private _color = getArray (_x >> "color");
    if (count _color >= 3) then {
        _rows set [configName _x, _color apply { if (_x isEqualType "") then { call compile _x } else { _x } }];
        if (count _rows >= 200) then { ["marker_colors"] call _flush };
    };
} forEach configProperties [configFile >> "CfgMarkerColors", "isClass _x", true];
["marker_colors"] call _flush;

private _mods = getLoadedModsInfo;  // [name, folder, default, official, ...]
private _header = createHashMap;
_header set ["game", (productVersion select [2, 2]) joinString "."];
_header set ["mods", (_mods select { !(_x select 2) }) apply { _x select 0 }];
"arma_aar" callExtension ["gd_done", [toJSON _header, toJSON values _textures, toJSON (_mods apply { _x select 1 }), toJSON _extraPaths]];

private _status = "busy";
private _until = diag_tickTime + 1800;
while { _status isEqualTo "busy" && diag_tickTime < _until } do {
    sleep 2;
    _status = "arma_aar" callExtension "gd_status";
};
diag_log format ["[AAR] game data export: %1", _status];
systemChat format ["[AAR] game data export: %1", _status];
