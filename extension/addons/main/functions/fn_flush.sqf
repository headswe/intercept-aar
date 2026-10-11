/*
 * Sends queued records to the extension in one call.
 */
if (aar_buffer isEqualTo []) exitWith {};
private _text = aar_buffer joinString toString [10];
aar_buffer = [];
private _result = "arma_aar" callExtension ["write", [_text]];
if ((_result select 1) != 0) then {
    diag_log format ["[AAR] write failed: %1", _result];
};
