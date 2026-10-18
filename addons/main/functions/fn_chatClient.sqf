/*
 * Client side of the chat recording. The server sends this code to every machine with a player
 * (aar_fnc_init), so clients need nothing installed; it must not call any other aar_ function,
 * because clients don't have them.
 *
 * Chat on side, command, group, vehicle, direct and custom channels only goes to the players on
 * that channel, so a dedicated server never sees most of it. So each player reports the messages
 * they type themselves, on any channel, to the server (aar_fnc_chatReport) in batches. Each entry
 * carries CBA_missionTime when it was sent, so the server records it at that time. Lines starting
 * with # are left out: they are server commands and can carry a password (#login).
 *
 * Entries: [channel, sender unit, sender name, from (as shown in the chat), text, CBA_missionTime]
 */
if (!hasInterface || {!isNil "aar_cc_ready"}) exitWith {};
aar_cc_ready = true;
aar_cc_buffer = [];
aar_cc_flushAt = 0;

addMissionEventHandler ["HandleChatMessage", {
    params ["_channel", "_owner", "_from", "_text", "_person", "_name", "", "", "_isPlayerMessage"];
    if (_isPlayerMessage && {_owner == clientOwner} && {_text isNotEqualTo ""} && {(_text select [0, 1]) != "#"}) then {
        aar_cc_buffer pushBack [_channel, _person, _name, _from, _text select [0, 1024], CBA_missionTime];
    };
    nil  // anything else returned would change or hide the message
}];

addMissionEventHandler ["EachFrame", {
    if (aar_cc_buffer isEqualTo [] || {diag_tickTime < aar_cc_flushAt}) exitWith {};
    aar_cc_flushAt = diag_tickTime + 0.5;
    private _batch = aar_cc_buffer;
    aar_cc_buffer = [];
    for "_i" from 0 to count _batch - 1 step 50 do {
        [_batch select [_i, 50]] remoteExecCall ["aar_fnc_chatReport", 2];
    };
}];
