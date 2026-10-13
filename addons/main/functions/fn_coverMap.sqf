/*
 * Records the area left uncovered by each Cover Map module (ModuleCoverMap_F) when it is first
 * seen and whenever it moves or changes size; the module's objectArea can change mid-mission.
 * The area is [a, b, angle] like triggerArea: half-sizes in metres and the rotation in degrees.
 * A module that was deleted gets one record with removed = true.
 *
 * Called with true at the start of the recording to find the modules, then every snapshot.
 */
params [["_find", false]];
if (_find) then {
    aar_coverMaps = (allMissionObjects "ModuleCoverMap_F") apply { [_x, []] };
};
{
    _x params ["_module", "_last"];
    private _key = str _forEachIndex;
    if (isNull _module) then {
        if (_last isNotEqualTo "removed") then {
            _x set [1, "removed"];
            ["cover_map", ["id", toJSON _key, "removed", "true"]] call aar_fnc_rec;
        };
        continue;
    };
    private _area = (_module getVariable ["objectArea", []]) select [0, 3];
    if (count _area < 3) then { continue };
    private _now = [_area, getPosASL _module];
    if (_now isEqualTo _last) then { continue };
    _x set [1, _now];
    ["cover_map", [
        "id", toJSON _key,
        "pos", (getPosASL _module) call aar_fnc_pos,
        "area", toJSON (_area apply { parseNumber (_x toFixed 1) })
    ]] call aar_fnc_rec;
} forEach aar_coverMaps;
