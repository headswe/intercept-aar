/*
 * Client side of the radio recording. The server sends this code to every machine with a player
 * (aar_fnc_init), so clients need nothing installed; it must not call any other aar_ function,
 * because clients don't have them.
 *
 * ACRE2 and TFAR only know about a transmission on the speaker's own machine (the voice goes
 * through TeamSpeak, not the game), so this listens to their local events and reports each
 * transmission start and end to the server (aar_fnc_radio). Every few seconds it also reports
 * the radios the player carries and the channel each is on, when that changed.
 *
 * A radio is reported as [id, class, display name, channel (1-based), channel name, frequency,
 * long range, additional channel].
 */
if (!hasInterface || {!isNil "aar_rc_ready"}) exitWith {};
aar_rc_ready = true;
aar_rc_acre = !isNil "acre_api_fnc_getCurrentRadioList";
aar_rc_tfar = !isNil "TFAR_fnc_radiosList";
if (!aar_rc_acre && !aar_rc_tfar) exitWith {};

// Each report carries CBA_missionTime, so the server records it when it happened.
aar_rc_send = { (_this + [CBA_missionTime]) remoteExecCall ["aar_fnc_radio", 2] };

aar_rc_acreRadio = {
    params ["_id"];
    private _base = [_id] call acre_api_fnc_getBaseRadio;
    private _data = [_id, "getCurrentChannelData"] call acre_sys_data_fnc_dataEvent;
    private _freq = 0;
    if (!isNil "_data") then {
        if (_data isEqualType locationNull) then { _freq = _data getVariable ["frequencyTX", 0] };
        if (_data isEqualType createHashMap) then { _freq = _data getOrDefault ["frequencyTX", 0] };
    };
    private _label = [_id, "getChannelDescription"] call acre_sys_data_fnc_dataEvent;
    if (isNil "_label" || {!(_label isEqualType "")}) then { _label = "" };
    [_id, _base, getText (configFile >> "CfgWeapons" >> _base >> "displayName"), [_id] call acre_api_fnc_getRadioChannel, _label, _freq, false, false]
};

aar_rc_tfarRadio = {
    params ["_radio", "_lr", ["_additional", false]];
    if (_lr) exitWith {
        _radio params ["_obj", "_settings"];
        private _channel = if (_additional) then { _radio call TFAR_fnc_getAdditionalLrChannel } else { _radio call TFAR_fnc_getLrChannel };
        private _class = typeOf _obj;
        [netId _obj + "/" + _settings, _class, getText (configFile >> "CfgVehicles" >> _class >> "displayName"),
            _channel + 1, "", [_radio, _channel + 1] call TFAR_fnc_getChannelFrequency, true, _additional]
    };
    private _channel = if (_additional) then { _radio call TFAR_fnc_getAdditionalSwChannel } else { _radio call TFAR_fnc_getSwChannel };
    // A TFAR handheld's class is numbered per radio (TFAR_anprc152_12); tf_parent is the model.
    private _class = getText (configFile >> "CfgWeapons" >> _radio >> "tf_parent");
    if (_class isEqualTo "") then { _class = _radio };
    [_radio, _class, getText (configFile >> "CfgWeapons" >> _radio >> "displayName"),
        _channel + 1, "", [_radio, _channel + 1] call TFAR_fnc_getChannelFrequency, false, _additional]
};

if (aar_rc_acre) then {
    aar_rc_acreTx = "";
    // [unit, on radio, radio id, speaking type]; the stop event does not say which radio.
    ["acre_startedSpeaking", {
        params ["_unit", "_onRadio", ["_radioId", ""]];
        if (!_onRadio || {_radioId isEqualTo ""}) exitWith {};
        aar_rc_acreTx = _radioId;
        ["tx_start", _unit, "acre", [_radioId] call aar_rc_acreRadio] call aar_rc_send;
    }] call CBA_fnc_addEventHandler;
    ["acre_stoppedSpeaking", {
        params ["_unit"];
        if (aar_rc_acreTx isEqualTo "") exitWith {};
        ["tx_end", _unit, "acre", [aar_rc_acreTx]] call aar_rc_send;
        aar_rc_acreTx = "";
    }] call CBA_fnc_addEventHandler;
};

if (aar_rc_tfar) then {
    // [unit, radio, 0 = handheld / 1 = long range, additional channel, pressed]
    ["TFAR_event_OnTangent", {
        params ["_unit", "_radio", "_type", "_additional", "_down"];
        if !(_type in [0, 1]) exitWith {};
        [["tx_end", "tx_start"] select _down, _unit, "tfar", [_radio, _type == 1, _additional] call aar_rc_tfarRadio] call aar_rc_send;
    }] call CBA_fnc_addEventHandler;
};

aar_rc_last = [];
[{
    private _unit = call CBA_fnc_currentUnit;
    if (!alive _unit) exitWith {};
    private _list = [];
    if (aar_rc_acre) then {
        { _list pushBack ([_x] call aar_rc_acreRadio) } forEach ([] call acre_api_fnc_getCurrentRadioList);
    };
    if (aar_rc_tfar) then {
        { _list pushBack ([_x, false] call aar_rc_tfarRadio) } forEach (_unit call TFAR_fnc_radiosList);
        { _list pushBack ([_x, true] call aar_rc_tfarRadio) } forEach (_unit call TFAR_fnc_lrRadiosList);
    };
    if ([_unit, _list] isEqualTo aar_rc_last) exitWith {};
    aar_rc_last = [_unit, _list];
    ["radios", _unit, ["tfar", "acre"] select aar_rc_acre, _list] call aar_rc_send;
}, 5] call CBA_fnc_addPerFrameHandler;
