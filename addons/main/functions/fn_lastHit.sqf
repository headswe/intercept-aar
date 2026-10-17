/*
 * Remembers the latest hit on a recorded unit or vehicle, so its killed record can carry the
 * weapon and distance, and credit someone when the engine gives no killer (aar_fnc_killed).
 * Called for projectile hits (aar_fnc_projectile, aar_fnc_projectileReport) and Hit events
 * (aar_fnc_hit). A Hit event right after a projectile hit by the same attacker keeps the
 * projectile's weapon and origin.
 *
 * Arguments: 0: target id <NUMBER>, 1: shooter id <NUMBER>, 2: instigator id <NUMBER>,
 *            3: weapon class, "" when unknown <STRING>, 4: where the shot came from (ASL), [] when unknown <ARRAY>,
 *            5: where it hit (ASL), [] when unknown <ARRAY>, 6: mission time <NUMBER>
 */
params ["_target", "_shooter", "_instigator", "_weapon", "_from", "_at", "_time"];
// Hits by nobody or by the target itself (falls, its own grenade) don't replace the attacker's.
if (_target <= 0 || {(([_instigator, _shooter] select (_instigator == 0)) in [0, _target])}) exitWith {};
if (_weapon isEqualTo "" && {_from isEqualTo []}) then {
    (aar_lastHits getOrDefault [_target, []]) params [["_s", 0], ["_i", 0], ["_w", ""], ["_f", []], ["_a", []], ["_t", -1e9]];
    if (abs (_time - _t) < 1 && {_s == _shooter || {_instigator != 0 && _i == _instigator}}) then {
        _weapon = _w; _from = _f; _at = _a;
        if (_instigator == 0) then { _instigator = _i };
    };
};
aar_lastHits set [_target, [_shooter, _instigator, _weapon, _from, _at, _time]];
