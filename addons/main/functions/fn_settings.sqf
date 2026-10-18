/*
 * preInit (CBA XEH): registers the recorder options as CBA settings, under "AAR" in
 * Options > Addon Options. They are server settings (set in the server's or the mission's
 * CBA settings) and read once by aar_fnc_init, so a change applies to the next mission.
 * A key in the mission's description.ext `class AAR` overrides its setting, see aar_fnc_init.
 * Each value is in aar_setting_<key>.
 */
private _add = {
    params ["_key", "_type", "_title", "_subcategory", "_valueInfo"];
    ["aar_setting_" + _key, _type, _title, ["AAR", _subcategory], _valueInfo, 1, {}, true] call CBA_fnc_addSetting;
};

["enabled", "CHECKBOX", ["Record missions", "Off: no mission is recorded."], "Recording", true] call _add;
["interval", "SLIDER", ["Snapshot interval", "Seconds between snapshots of every unit and vehicle."], "Recording", [0.1, 10, 1, 1]] call _add;
["keyframeInterval", "SLIDER", ["Keyframe interval", "Seconds between full snapshots."], "Recording", [1, 600, 60, 0]] call _add;
["pauseWhenEmpty", "CHECKBOX", ["Pause when empty", "Dedicated server: no snapshots while no players are connected."], "Recording", true] call _add;

["logProjectiles", "CHECKBOX", ["Projectiles", "shot / proj_hit / proj_splash / proj_end records."], "Events", true] call _add;
["logHits", "CHECKBOX", ["Hits", "hit records."], "Events", true] call _add;
["logMarkers", "CHECKBOX", ["Markers", "Map markers, from the editor and placed or drawn by players."], "Events", true] call _add;
["logAI", "CHECKBOX", ["AI behaviour", "combat_mode / enemy_detected / fleeing for AI groups."], "Events", true] call _add;
["enemyDetectedCooldown", "SLIDER", ["Enemy detected cooldown", "Seconds before a group re-detecting the same target is logged again. 0 = every time."], "Events", [0, 600, 120, 0]] call _add;
["logRadio", "CHECKBOX", ["Radio", "radio_tx / radios / radio_nets with ACRE2 or TFAR."], "Events", true] call _add;
["logChat", "CHECKBOX", ["Chat", "What players type on every channel, plus system and script messages the server sees."], "Events", true] call _add;

["frameBudget", "SLIDER", ["Frame budget (ms)", "Recorder work per frame; snapshots are spread over frames to stay near it."], "Performance", [0.1, 20, 2, 1]] call _add;
["spikeThreshold", "SLIDER", ["Spike threshold (ms)", "Server frames slower than this get a perf_spike record and an RPT line."], "Performance", [1, 1000, 100, 0]] call _add;
