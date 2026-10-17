class CfgPatches {
    class arma_aar_main {
        name = "Arma AAR Recorder";
        units[] = {};
        weapons[] = {};
        requiredVersion = 2.18;
        requiredAddons[] = {"A3_Functions_F"};
        author = "headswe";
        version = "0.1";
        versionStr = "0.1.0";
        versionAr[] = {0,1,0};
    };
};

class CfgFunctions {
    class aar {
        tag = "aar";
        class main {
            file = "\z\arma_aar\addons\main\functions";
            class init { postInit = 1; };
            class rec {};
            class pos {};
            class id {};
            class knownId {};
            class register {};
            class snapshot {};
            class projectile {};
            class projectileReport {};
            class projectileClient { headerType = -1; };  // sent to clients as code, so no function header
            class flush {};
            class frame {};
            class hit {};
            class hitReport {};
            class hitClient { headerType = -1; };  // sent to clients as code, so no function header
            class lastHit {};
            class killed {};
            class unconscious {};
            class registerGroup {};
            class groupEvent {};
            class groupClient { headerType = -1; };  // sent to clients as code, so no function header
            class groupFields {};
            class orbat {};
            class tmfFields {};
            class tmfLoadout {};
            class tmfGroupFields {};
            class radio {};
            class radioClient { headerType = -1; };  // sent to clients as code, so no function header
            class radioNets {};
            class markerFields {};
            class skipMarker {};
            class marker {};
            class markerClient { headerType = -1; };  // sent to clients as code, so no function header
            class coverMap {};
            class stop {};
        };
    };
};

// Clients report radio transmissions (aar_fnc_radio), their markers off the Global channel
// (aar_fnc_marker), the projectiles their units fire (aar_fnc_projectileReport), hits on their
// units and vehicles (aar_fnc_hitReport) and the AI events of the groups they run
// (aar_fnc_groupEvent) to the server. Allowed here for servers that
// whitelist remote execution; a mission with its own CfgRemoteExec in whitelist mode must list it too.
class CfgRemoteExec {
    class Functions {
        class aar_fnc_radio { allowedTargets = 2; jip = 0; };
        class aar_fnc_marker { allowedTargets = 2; jip = 0; };
        class aar_fnc_projectileReport { allowedTargets = 2; jip = 0; };
        class aar_fnc_groupEvent { allowedTargets = 2; jip = 0; };
        class aar_fnc_hitReport { allowedTargets = 2; jip = 0; };
    };
};
