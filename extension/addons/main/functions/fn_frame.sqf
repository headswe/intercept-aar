/*
 * EachFrame handler. Starts a snapshot every aar_interval seconds and advances it by a batch
 * of entities per frame, sized so the recorder's work in one frame stays near aar_frameBudget
 * milliseconds. Flushes queued records, writes a perf record once per snapshot and a
 * perf_spike record (plus an RPT line) whenever a server frame takes longer than
 * aar_spikeThreshold milliseconds.
 */
if (!aar_active) exitWith {};

// diag_deltaTime is the previous frame, so compare it with the recorder's work in that frame.
private _frameMs = diag_deltaTime * 1000;
if (_frameMs >= aar_spikeThreshold) then {
    ["perf_spike", [
        "frame_ms", _frameMs toFixed 1,
        "recorder_ms", aar_lastWorkMs toFixed 2,
        "fps", diag_fps toFixed 1,
        "units", toJSON count allUnits,
        "entities", toJSON count aar_entities
    ]] call aar_fnc_rec;
    diag_log format ["[AAR] frame spike: %1 ms (recorder %2 ms, %3 units)", _frameMs toFixed 1, aar_lastWorkMs toFixed 2, count allUnits];
};
aar_lastWorkMs = 0;

private _t = time;
private _working = aar_snap isNotEqualTo [];
if (!_working && {_t - aar_lastSnapshot >= aar_interval}) then {
    aar_lastSnapshot = _t;
    private _keyframe = _t - aar_lastKeyframe >= aar_keyframeInterval;
    if (_keyframe) then { aar_lastKeyframe = _t };
    "arma_aar" callExtension "tick";
    // Register anything new; one getVariable per object, the rest is skipped.
    {
        if ((_x getVariable ["aar_id", 0]) == 0) then { _x call aar_fnc_register };
    } forEach (allUnits + vehicles);
    aar_snap = [_t, _keyframe, keys aar_entities, 0, [], []];
    aar_snapStats = [0, 0, 0];  // frames, total ms, max ms
    _working = true;
} else {
    if (_working) then { "arma_aar" callExtension "tick" };
};

private _done = _working && {call aar_fnc_snapshot};
if (_done) then { aar_snap = [] };

private _us = [_working] call aar_fnc_flush;
if (_working && _us >= 0) then {
    private _ms = _us / 1000;
    aar_lastWorkMs = _ms;
    aar_snapStats params ["_frames", "_total", "_max"];
    aar_snapStats = [_frames + 1, _total + _ms, _max max _ms];
    // Keep each frame's share near the budget: shrink fast when over, grow slowly when well under.
    if (_ms > aar_frameBudget) then {
        aar_batch = (floor (aar_batch / 2)) max 10;
    } else {
        if (_ms < aar_frameBudget / 2) then { aar_batch = ceil (aar_batch * 1.25) min 2000 };
    };
};

if (_done) then {
    aar_snapStats params ["_frames", "_total", "_max"];
    // Queued now, written with the next frame's flush.
    ["perf", [
        "fps", diag_fps toFixed 1,
        "fps_min", diag_fpsMin toFixed 1,
        "units", toJSON count allUnits,
        "entities", toJSON count aar_entities,
        "projectiles", toJSON count aar_projShooters,
        "snap_frames", toJSON _frames,
        "snap_ms", _total toFixed 2,
        "snap_max_ms", _max toFixed 2,
        "batch", toJSON aar_batch
    ]] call aar_fnc_rec;
};
