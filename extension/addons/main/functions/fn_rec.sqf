/*
 * Queues one record. Values in _fields must already be JSON text: str for strings,
 * booleans and small integers, toFixed for decimals, aar_fnc_pos for positions.
 * The extension fixes SQF's string quoting when it writes the line.
 *
 * Arguments: 0: type <STRING>, 1: [key, value, key, value, ...] <ARRAY>
 */
params ["_type", ["_fields", []]];

private _parts = ['{"type":"', _type, '","t":', time toFixed 2];
for "_i" from 0 to (count _fields - 2) step 2 do {
    _parts append [',"', _fields select _i, '":', _fields select (_i + 1)];
};
_parts pushBack "}";
aar_buffer pushBack (_parts joinString "");
