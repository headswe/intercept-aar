/*
 * Writes one chat message as a `chat` record.
 * Channels: 0 global, 1 side, 2 command, 3 group, 4 vehicle, 5 direct, 6-15 custom (radioChannelCreate),
 * 16 system, 17 BattlEye. Side, command, group and vehicle messages also record who they went to:
 * the sender's side, group or vehicle when it was sent.
 *
 * Arguments: 0: channel <NUMBER>, 1: sender unit <OBJECT>, 2: sender name <STRING>, 3: from, as the chat
 * shows it <STRING>, 4: text <STRING>, 5: typed by a player <BOOL>, 6: mission time (default: now) <NUMBER>
 */
params [["_channel", -1, [0]], ["_person", objNull, [objNull]], ["_name", "", [""]], ["_from", "", [""]],
    ["_text", "", [""]], ["_player", false, [false]], ["_time", CBA_missionTime, [0]]];

private _fields = ["channel", toJSON round _channel, "text", toJSON (_text select [0, 1024])];
if (_channel in [6, 7, 8, 9, 10, 11, 12, 13, 14, 15]) then {
    private _label = (radioChannelInfo (_channel - 5)) param [1, ""];
    if (_label isEqualType "" && {_label isNotEqualTo ""}) then { _fields append ["channel_name", toJSON (_label select [0, 64])] };
};
private _unit = _person call aar_fnc_id;
if (_unit != 0) then { _fields append ["unit", toJSON _unit] };
// Who the message went to, from the sender's unit.
if (!isNull _person) then {
    switch (_channel) do {
        case 1;
        case 2: { _fields append ["to_side", toJSON str side group _person] };
        case 3: { _fields append ["to_group", toJSON groupId group _person, "to_side", toJSON str side group _person] };
        case 4: {
            private _veh = objectParent _person;
            if (!isNull _veh) then { _fields append ["to_vehicle", toJSON (_veh call aar_fnc_id)] };
        };
    };
};
if (_name isNotEqualTo "") then { _fields append ["name", toJSON (_name select [0, 64])] };
if (_from isNotEqualTo "" && {_from isNotEqualTo _name}) then { _fields append ["from", toJSON (_from select [0, 128])] };
if (_player) then { _fields append ["player", "true"] };
["chat", _fields, _time] call aar_fnc_rec;
