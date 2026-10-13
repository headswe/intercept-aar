/*
 * Writes TMF's ACRE2 radio networks (mission attribute TMF_AcreSettings) as one radio_nets record.
 * Units carry radio_net and radio_channels pointing into it; see aar_fnc_tmfGroupFields.
 *
 * Network in TMF: [conditions (sides as numbers or sides, factions as strings), [channels]]
 * Channel in TMF: [short name, description, radio class, conditions, shared]
 *
 * Each network is an ACRE preset (tmf_preset<index>) with its channels numbered in order per
 * radio family, so the frequency of every channel can be read back from the preset once TMF has
 * built them (tmf_acre2_networksCreated).
 */
private _core = missionNamespace getVariable ["tmf_acre2_radioCoreSettings", []];
private _hasAcre = !isNil "acre_api_fnc_getPresetChannelField";
private _nets = [];
{
    _x params [["_conditions", []], ["_channels", []]];
    private _preset = format ["tmf_preset%1", _forEachIndex];
    private _numbers = createHashMap;   // radio family -> channels so far
    private _list = [];
    {
        _x params [["_name", ""], ["_description", ""], ["_radio", ""], "", ["_shared", false]];
        private _family = _core findIf { _radio in (_x select 0) };
        private _number = (_numbers getOrDefault [_family, 0]) + 1;
        _numbers set [_family, _number];
        private _channel = createHashMapFromArray [["name", _name], ["description", _description], ["radio", _radio], ["shared", _shared], ["number", _number]];
        if (_hasAcre && {_family >= 0}) then {
            private _freq = [_radio, _preset, _number, "frequencyTX"] call acre_api_fnc_getPresetChannelField;
            if (!isNil "_freq" && {_freq isEqualType 0}) then { _channel set ["freq", round (_freq * 1e5) / 1e5] };
        };
        _list pushBack _channel;
    } forEach _channels;
    private _sides = [];
    private _factions = [];
    {
        switch (true) do {
            case (_x isEqualType 0): { if (_x >= 0) then { _sides pushBackUnique str ([east, west, independent, civilian] param [_x, sideUnknown]) } };
            case (_x isEqualType west): { _sides pushBackUnique str _x };
            case (_x isEqualType ""): { _factions pushBackUnique _x };
        };
    } forEach _conditions;
    _nets pushBack createHashMapFromArray [["index", _forEachIndex], ["sides", _sides], ["factions", _factions], ["channels", _list]];
} forEach aar_tmfNets;

["radio_nets", ["source", toJSON "tmf", "nets", toJSON _nets]] call aar_fnc_rec;
