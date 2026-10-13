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
            class flush {};
            class frame {};
            class hit {};
            class addMPHit {};
            class registerGroup {};
            class groupFields {};
            class orbat {};
            class tmfFields {};
            class tmfLoadout {};
            class tmfGroupFields {};
            class radio {};
            class radioClient { headerType = -1; };  // sent to clients as code, so no function header
            class radioNets {};
            class stop {};
        };
    };
};

// Clients report radio transmissions to the server (aar_fnc_radio). Allowed here for servers that
// whitelist remote execution; a mission with its own CfgRemoteExec in whitelist mode must list it too.
class CfgRemoteExec {
    class Functions {
        class aar_fnc_radio { allowedTargets = 2; jip = 0; };
    };
};
