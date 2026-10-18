/*
 * Writes a net record: the engine's network stats for every connected client (players and
 * headless clients) from getUserInfo, and on Linux the operating system's queues for the
 * server's UDP sockets. Called by the frame handler every aar_netInterval seconds; reads only
 * what the server already has, so it sends nothing to clients.
 */
private _clients = [];
{
    private _info = getUserInfo _x;
    if (_info isEqualTo []) then { continue };
    _info params ["", "_owner", "", "", "", "", "", ["_hc", false], "", ["_net", []], ["_unit", objNull]];
    if (_owner == clientOwner || {!(_net isEqualType [])} || {_net isEqualTo []}) then { continue };  // the server itself
    _net params [["_ping", 0], ["_bandwidth", 0], ["_desync", 0]];
    _clients pushBack [_owner, _unit call aar_fnc_knownId, round _ping, round _bandwidth, round _desync, _hc];
} forEach allUsers;

private _fields = ["clients", toJSON _clients];
// ["rx_queue", "tx_queue", "drops"] as number text, "" where the extension can't read them (Windows).
private _queues = "arma_aar" callExtension "netq";
if (_queues isNotEqualTo "") then {
    (parseSimpleArray _queues) params ["_rx", "_tx", "_drops"];
    _fields append ["udp_rx", _rx, "udp_tx", _tx, "udp_drops", _drops];
};
["net", _fields] call aar_fnc_rec;
