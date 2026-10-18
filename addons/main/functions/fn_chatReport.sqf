/*
 * Writes a batch of chat messages reported by a client (sent by the code in aar_fnc_chatClient):
 * the messages that player typed. A message whose sender unit the sending machine does not own
 * is dropped.
 *
 * Arguments: 0: entries <ARRAY>, see aar_fnc_chatClient
 */
params [["_batch", [], [[]]]];
if (!aar_active || {!aar_logChat}) exitWith {};
private _sender = if (isMultiplayer && {isRemoteExecuted}) then { remoteExecutedOwner } else { -1 };

{
    if !(_x isEqualType []) then { continue };
    _x params [["_channel", -1, [0]], ["_person", objNull, [objNull]], ["_name", "", [""]], ["_from", "", [""]],
        ["_text", "", [""]], ["_time", CBA_missionTime, [0]]];
    if (_text isEqualTo "" || {_sender >= 0 && {!isNull _person} && {owner _person != _sender}}) then { continue };
    [_channel, _person, _name, _from, _text, true, _time call aar_fnc_reportTime] call aar_fnc_chat;
} forEach (_batch select [0, 100]);
