/*
 * Writes a killed record. Called from EntityKilled, or with ACE medical once ACE's ace_killed
 * event has said who ACE credits (aar_fnc_init), which is usually a moment later.
 *
 * Credit: the instigator, else the killer, as given. When that is nobody or the victim itself
 * (bleeding out, a fall or fire after being shot), the last recorded hit on the victim within
 * five minutes is credited instead and `credit` says "last_hit". The weapon and distance come
 * from the last hit when it was by whoever is credited; without one, the distance is between
 * the two at the time of death.
 *
 * Arguments: 0: victim <OBJECT>, 1: killer <OBJECT>, 2: instigator <OBJECT>, 3: credit, "engine" or "ace" <STRING>,
 *            4: ACE cause of death, "" without ACE <STRING>, 5: mission time <NUMBER>, 6: victim position (ASL) <ARRAY>
 */
params ["_obj", "_killerObj", "_instigatorObj", "_credit", "_cause", "_time", "_pos"];
private _victim = _obj call aar_fnc_id;
if (_victim == 0) exitWith {};
private _killer = _killerObj call aar_fnc_id;
private _instigator = _instigatorObj call aar_fnc_id;
private _last = aar_lastHits getOrDefault [_victim, []];
aar_lastHits deleteAt _victim;

private _by = [_instigator, _killer] select (_instigator == 0);
if ((_by == 0 || _by == _victim) && {_last isNotEqualTo []} && {_time - (_last select 5) <= 300}) then {
    _killer = _last select 0;
    _instigator = _last select 1;
    _by = [_instigator, _killer] select (_instigator == 0);
    _credit = "last_hit";
};

private _fields = [
    "victim", toJSON _victim,
    "killer", toJSON _killer,
    "instigator", toJSON _instigator,
    "pos", _pos call aar_fnc_pos,
    "credit", toJSON _credit
];
if (_cause isNotEqualTo "") then { _fields append ["cause", toJSON _cause] };

if (_by != 0 && _by != _victim) then {
    private _weapon = "";
    private _distance = -1;
    if (_last isNotEqualTo [] && {(_last select 0) == _killer || {(_last select 1) == _by}}) then {
        _last params ["", "", "_w", "_from", "_at"];
        _weapon = _w;
        if (_from isNotEqualTo []) then { _distance = _from vectorDistance ([_at, _pos] select (_at isEqualTo [])) };
    };
    if (_distance < 0) then {
        private _byObj = (aar_entities getOrDefault [_by, [objNull]]) select 0;
        if (!isNull _byObj) then { _distance = (getPosASL _byObj) vectorDistance _pos };
    };
    if (_weapon isNotEqualTo "") then {
        _fields append ["weapon", toJSON _weapon, "weapon_name", toJSON getText (configFile >> "CfgWeapons" >> _weapon >> "displayName")];
    };
    if (_distance >= 0) then { _fields append ["distance", _distance toFixed 1] };
};
["killed", _fields, _time] call aar_fnc_rec;
