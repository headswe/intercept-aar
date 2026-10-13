/*
 * Writes a radio report from a client (sent by the code in aar_fnc_radioClient):
 *   "tx_start": a transmission started; data is the radio, see aar_fnc_radioClient
 *   "tx_end":   it ended; data is [radio id]
 *   "radios":   the radios the unit carries now; data is a list of radios
 * Reports about a unit the sending machine does not own are dropped, and an end without a
 * start is ignored.
 *
 * Arguments: 0: kind <STRING>, 1: unit <OBJECT>, 2: radio system, "acre" or "tfar" <STRING>, 3: data <ARRAY>
 */
params [["_kind", "", [""]], ["_unit", objNull, [objNull]], ["_system", "", [""]], ["_data", [], [[]]]];
if (!aar_active || {isNull _unit} || {!(_system in ["acre", "tfar"])}) exitWith {};
if (isMultiplayer && {isRemoteExecuted} && {remoteExecutedOwner != owner _unit}) exitWith {};
private _id = _unit call aar_fnc_id;
if (_id == 0) exitWith {};

// One radio as record fields.
private _fnc_radio = {
    params [["_rid", "", [""]], ["_class", "", [""]], ["_name", "", [""]], ["_channel", -1, [0]], ["_label", "", [""]],
        ["_freq", 0, [0, ""]], ["_lr", false, [false]], ["_additional", false, [false]]];
    if (_freq isEqualType "") then { _freq = parseNumber _freq };
    private _fields = ["radio_id", toJSON (_rid select [0, 64]), "radio", toJSON (_class select [0, 64]), "radio_name", toJSON (_name select [0, 64]),
        "channel", toJSON round _channel, "freq", _freq toFixed 5];
    if (_label isNotEqualTo "") then { _fields append ["channel_name", toJSON (_label select [0, 64])] };
    if (_lr) then { _fields append ["lr", "true"] };
    if (_additional) then { _fields append ["additional", "true"] };
    _fields
};

private _key = str _id + " " + str (_data param [0, ""]);
switch (_kind) do {
    case "tx_start": {
        if !((_data param [0, ""]) isEqualType "") exitWith {};
        aar_radioOpen set [_key, true];
        ["radio_tx", ["unit", toJSON _id, "system", toJSON _system] + (_data call _fnc_radio)] call aar_fnc_rec;
    };
    case "tx_end": {
        if (isNil { aar_radioOpen deleteAt _key }) exitWith {};
        ["radio_tx_end", ["unit", toJSON _id, "system", toJSON _system, "radio_id", toJSON (_data select 0)]] call aar_fnc_rec;
    };
    case "radios": {
        private _radios = [];
        {
            if (_x isEqualType []) then {
                private _fields = _x call _fnc_radio;
                private _pairs = [];
                for "_i" from 0 to (count _fields - 2) step 2 do { _pairs pushBack (toJSON (_fields select _i) + ":" + (_fields select (_i + 1))) };
                _radios pushBack ("{" + (_pairs joinString ",") + "}");
            };
        } forEach (_data select [0, 16]);
        ["radios", ["unit", toJSON _id, "system", toJSON _system, "radios", "[" + (_radios joinString ",") + "]"]] call aar_fnc_rec;
    };
};
