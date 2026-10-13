/*
 * A marker's full state as record fields: text, type, colour, shape, brush, size, direction,
 * alpha, position, and for polylines (lines drawn on the map) the points as [x1,y1,x2,y2,...].
 *
 * Arguments: marker name <STRING>
 */
params ["_marker"];
private _shape = markerShape _marker;
private _fields = [
    "marker", toJSON _marker,
    "text", toJSON markerText _marker,
    "markerType", toJSON markerType _marker,
    "color", toJSON markerColor _marker,
    "shape", toJSON _shape,
    "brush", toJSON markerBrush _marker,
    "size", toJSON ((markerSize _marker) apply { parseNumber (_x toFixed 2) }),
    "dir", (markerDir _marker) toFixed 1,
    "alpha", (markerAlpha _marker) toFixed 2,
    "pos", (getMarkerPos _marker) call aar_fnc_pos
];
if (_shape == "POLYLINE") then {
    _fields append ["line", toJSON ((markerPolyline _marker) apply { parseNumber (_x toFixed 1) })];
};
_fields
