/*
 * Adds the server's handlers for ACE events raised on every machine: captives and explosives.
 * Events raised on one machine only (wounds, treatment, dragging, fireteam colours) are reported
 * by aar_fnc_aceClient. Called by aar_fnc_init when ACE is loaded and logACE is on.
 *
 *   captive: unit, captive <BOOL>, reason ("SetHandcuffed" or "SetSurrendered"), by
 *   explosive: action ("placed", "armed", "defusing", "defused", "defuse_exploded"), explosive
 *              (a number per armed explosive), class (magazine when placed, otherwise the
 *              explosive's type), by, pos
 *   tripflare: pos
 */
aar_aceExplosive = {
    params ["_action", "_obj", "_unit", ["_class", ""]];
    // A defused or blown up explosive is usually already deleted by the time the event reaches the
    // server, so it is then recorded at the unit, without its number or class.
    if (!aar_active || {isNull _obj && {isNull _unit}}) exitWith {};
    private _xid = _obj getVariable ["aar_xid", 0];
    if (_xid == 0 && {!isNull _obj} && {_action != "placed"}) then {
        _xid = aar_nextXid;
        aar_nextXid = aar_nextXid + 1;
        _obj setVariable ["aar_xid", _xid];
    };
    if (_class isEqualTo "" && {!isNull _obj}) then { _class = typeOf _obj };
    private _fields = ["action", toJSON _action, "pos", (getPosASL ([_obj, _unit] select (isNull _obj))) call aar_fnc_pos];
    if (_class isNotEqualTo "") then { _fields append ["class", toJSON _class] };
    if (_xid != 0) then { _fields append ["explosive", toJSON _xid] };
    private _by = _unit call aar_fnc_id;
    if (_by != 0) then { _fields append ["by", toJSON _by] };
    ["explosive", _fields] call aar_fnc_rec;
};
aar_nextXid = 1;

["ace_captiveStatusChanged", {
    params [["_unit", objNull, [objNull]], ["_state", false, [false]], ["_reason", "", [""]], ["_caller", objNull, [objNull]]];
    if (!aar_active || {isNull _unit}) exitWith {};
    private _fields = ["unit", toJSON (_unit call aar_fnc_id), "captive", toJSON _state, "reason", toJSON _reason, "pos", (getPosASL _unit) call aar_fnc_pos];
    private _by = _caller call aar_fnc_id;
    if (_by != 0 && {_caller != _unit}) then { _fields append ["by", toJSON _by] };
    ["captive", _fields] call aar_fnc_rec;
}] call CBA_fnc_addEventHandler;

["ace_explosives_setup", {
    params [["_obj", objNull, [objNull]], ["_magazine", "", [""]], ["_unit", objNull, [objNull]]];
    ["placed", _obj, _unit, _magazine] call aar_aceExplosive;
}] call CBA_fnc_addEventHandler;
["ace_explosives_place", {
    params [["_obj", objNull, [objNull]], "", "", ["_unit", objNull, [objNull]]];
    ["armed", _obj, _unit] call aar_aceExplosive;
}] call CBA_fnc_addEventHandler;
{
    _x params ["_event", "_action"];
    [_event, compile format ['
        params [["_obj", objNull, [objNull]], ["_unit", objNull, [objNull]]];
        ["%1", _obj, _unit] call aar_aceExplosive;
    ', _action]] call CBA_fnc_addEventHandler;
} forEach [["ace_explosives_defuseStart", "defusing"], ["ace_explosives_defuse", "defused"], ["ace_explosives_explodeOnDefuse", "defuse_exploded"]];

["ace_tripflareTriggered", {
    params ["", ["_posAGL", [], [[]], 3]];
    if (!aar_active || {_posAGL isEqualTo []}) exitWith {};
    ["tripflare", ["pos", (AGLToASL _posAGL) call aar_fnc_pos]] call aar_fnc_rec;
}] call CBA_fnc_addEventHandler;
