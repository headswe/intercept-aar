/*
 * Sends queued records to the extension in one call. With _timed, calls it even when nothing
 * is queued, because the reply carries the time since the last "tick".
 *
 * Arguments: 0: timed <BOOL>
 * Returns: microseconds since the last tick, or -1 <NUMBER>
 */
params [["_timed", false]];
if (aar_buffer isEqualTo [] && !_timed) exitWith {-1};
private _text = aar_buffer joinString toString [10];
aar_buffer = [];
private _result = "arma_aar" callExtension ["write", [_text]];
_result params ["_output", "_code"];
if (_code != 0) exitWith {
    diag_log format ["[AAR] write failed: %1", _result];
    -1
};
if (_output isEqualTo "") then { -1 } else { parseNumber _output }
