/*
 * The mission time to record a client-reported event at. Clients stamp each event with
 * CBA_missionTime when it happens, which CBA keeps in step with the server's, so the record
 * gets the time of the event rather than the time its batch arrived. A stamp from the future or
 * from more than 10 seconds ago (a bad clock or a made-up value) is held to that window, and a
 * missing one is now.
 *
 * Arguments: 0: CBA_missionTime on the client when the event happened <NUMBER>
 * Return: mission time <NUMBER>
 */
params [["_t", CBA_missionTime]];
if !(_t isEqualType 0) exitWith { CBA_missionTime };
(_t min CBA_missionTime) max (CBA_missionTime - 10)
