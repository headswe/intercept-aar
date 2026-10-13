/*
 * Fields every record about a group carries: its name, side and current leader.
 *
 * Arguments: 0: group <GROUP>
 * Returns: [key, value, ...] for aar_fnc_rec <ARRAY>
 */
params ["_group"];
["group", toJSON groupId _group, "side", toJSON str side _group, "leader", toJSON (leader _group call aar_fnc_id)]
