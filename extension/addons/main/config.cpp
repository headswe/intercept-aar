class CfgPatches {
    class arma_aar_main {
        name = "Arma AAR Recorder";
        units[] = {};
        weapons[] = {};
        requiredVersion = 2.10;
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
            class stop {};
        };
    };
};
