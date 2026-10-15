/*
 * Whether a marker is left out of the recording. The marker event handlers' "local" flag says
 * where a change came from, not whether the marker is local-only: it is true for every marker
 * the server's own scripts create, move or delete, so it cannot be used to skip anything, and
 * markers local to the server cannot be told apart from global ones. The only common ones are
 * the Cover Map module's shading, which is recorded as cover_map instead, so those are skipped
 * by name.
 *
 * Arguments: marker name <STRING>
 */
(toLowerANSI _this) find "bis_fnc_modulecovermap" == 0
