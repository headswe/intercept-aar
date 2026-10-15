/*
 * Client side of the marker recording. The server sends this code to every machine with a player
 * (aar_fnc_init), so clients need nothing installed; it must not call any other aar_ function,
 * because clients don't have them.
 *
 * Markers players draw on any channel but Global (side, command, group, vehicle, direct) never
 * reach the server: only the players on that channel get them. So the player who places, moves
 * or deletes one reports it to the server (aar_fnc_marker). Global markers and markers made by
 * scripts with createMarker reach the server on their own and are left to it.
 *
 * A marker's state is [name, text, type, colour, shape, brush, size, dir, alpha, position,
 * polyline, channel].
 */
if (!hasInterface || {!isNil "aar_mc_ready"}) exitWith {};
aar_mc_ready = true;

aar_mc_state = {
    [_this, markerText _this, markerType _this, markerColor _this, markerShape _this, markerBrush _this,
        markerSize _this, markerDir _this, markerAlpha _this, getMarkerPos _this, markerPolyline _this, markerChannel _this]
};
// Channels 1 and up: user markers off Global (0); script-made markers have -1.
aar_mc_send = {
    params ["_kind", "_marker"];
    if (markerChannel _marker < 1) exitWith {};
    [_kind, _marker call aar_mc_state] remoteExecCall ["aar_fnc_marker", 2];
};

addMissionEventHandler ["MarkerCreated", {
    params ["_marker", "_channel", "_owner", "_local"];
    if (_local) then { ["created", _marker] call aar_mc_send };
}];
addMissionEventHandler ["MarkerUpdated", {
    params ["_marker", "_local"];
    if (_local) then { ["updated", _marker] call aar_mc_send };
}];
addMissionEventHandler ["MarkerDeleted", {
    params ["_marker", "_local"];
    if (_local) then { ["deleted", _marker] call aar_mc_send };
}];

// Markers this player drew before the code arrived (in the briefing, or before the recording
// started). User marker names are "_USER_DEFINED #<player id>/<marker id>/<channel>".
[] spawn {
    waitUntil { !isNull player };
    private _mine = "_USER_DEFINED #" + getPlayerID player + "/";
    {
        if (_x find _mine == 0) then { ["created", _x] call aar_mc_send };
    } forEach allMapMarkers;
};
