/*
 * Position as JSON text, in centimetres: "[x,y,z]".
 *
 * Arguments: position <ARRAY>
 */
format ["[%1,%2,%3]", (_this param [0, 0]) toFixed 2, (_this param [1, 0]) toFixed 2, (_this param [2, 0]) toFixed 2]
