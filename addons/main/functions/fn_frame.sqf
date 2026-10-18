/*
 * EachFrame handler. Starts a snapshot every aar_interval seconds and advances it by a batch
 * of entities per frame, sized so the recorder's work in one frame stays near aar_frameBudget
 * milliseconds. Flushes queued records, writes a perf record once per snapshot and a
 * perf_spike record (plus an RPT line) whenever a server frame takes longer than
 * aar_spikeThreshold milliseconds. Pauses snapshots while a dedicated server is empty.
 */
if (!aar_active) exitWith {};
// Times this handler's work in every frame, read back by the flush at the end.
"arma_aar" callExtension "tick";

// diag_deltaTime is the previous frame, so compare it with the recorder's work in that frame.
// The recorder's share covers this handler (snapshot and writing), not its event handlers.
private _frameMs = diag_deltaTime * 1000;
if (_frameMs >= aar_spikeThreshold) then {
    private _players = count (allPlayers - entities "HeadlessClient_F");
    ["perf_spike", [
        "frame_ms", _frameMs toFixed 1,
        "recorder_ms", aar_lastWorkMs toFixed 2,
        "fps", diag_fps toFixed 1,
        "units", toJSON count allUnits,
        "players", toJSON _players,
        "entities", toJSON count aar_entities,
        "projectiles", toJSON count aar_projShooters
    ]] call aar_fnc_rec;
    diag_log format ["[AAR] frame spike: %1 ms (recorder %2 ms, %3 units, %4 players, %5 projectiles)",
        _frameMs toFixed 1, aar_lastWorkMs toFixed 2, count allUnits, _players, count aar_projShooters];
};
aar_lastWorkMs = 0;

// On a dedicated server with nobody connected, stop taking snapshots so an empty server
// doesn't grow the file all night. The first snapshot after someone joins is a keyframe.
if (aar_pauseWhenEmpty && isDedicated) then {
    private _idle = (allPlayers - entities "HeadlessClient_F") isEqualTo [];
    if (_idle isNotEqualTo aar_idle) then {
        aar_idle = _idle;
        ["idle", ["idle", toJSON _idle]] call aar_fnc_rec;
        if (!_idle) then { aar_lastKeyframe = -1e9 };
    };
};

// TMF builds its ACRE presets a few frames into the mission; the frequencies come from them.
if (aar_radioNetsPending && {!isNil "tmf_acre2_networksCreated" || CBA_missionTime > 30}) then {
    aar_radioNetsPending = false;
    call aar_fnc_radioNets;
};

// Kills still waiting for ACE's credit (see EntityKilled in aar_fnc_init).
if (count aar_pendingKills > 0) then {
    {
        _y params ["_obj", "_killer", "_instigator", "_time", "_pos"];
        if (CBA_missionTime - _time > 3) then {
            aar_pendingKills deleteAt _x;
            [_obj, _killer, _instigator, "engine", "", _time, _pos] call aar_fnc_killed;
        };
    } forEach +aar_pendingKills;
};

private _t = CBA_missionTime;
private _working = aar_snap isNotEqualTo [];
if (!_working && {!aar_idle} && {_t - aar_lastSnapshot >= aar_interval}) then {
    aar_lastSnapshot = _t;
    private _keyframe = _t - aar_lastKeyframe >= aar_keyframeInterval;
    if (_keyframe) then { aar_lastKeyframe = _t };
    call aar_fnc_coverMap;
    // EntityCreated registers new objects as they appear; this sweep on keyframes only
    // catches anything created before the handler was added or that it missed.
    if (_keyframe) then {
        {
            if ((_x getVariable ["aar_id", 0]) == 0) then { _x call aar_fnc_register };
        } forEach (allUnits + vehicles);
        if (aar_logAI) then {
            { if (local _x) then { _x call aar_fnc_registerGroup } } forEach allGroups;
        };
    };
    aar_snap = [_t, _keyframe, keys aar_entities, 0, [], []];
    aar_snapStats = [0, 0, 0];  // frames, total ms, max ms
    _working = true;
};

private _done = _working && {call aar_fnc_snapshot};
if (_done) then { aar_snap = [] };

private _us = [true] call aar_fnc_flush;
if (_us >= 0) then { aar_lastWorkMs = _us / 1000 };
if (_working && _us >= 0) then {
    private _ms = _us / 1000;
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
