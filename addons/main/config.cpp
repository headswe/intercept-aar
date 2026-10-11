class CfgPatches {
    class intercept_aar_main {
        name = "Intercept AAR Recorder";
        units[] = {};
        weapons[] = {};
        requiredVersion = 2.0;
        requiredAddons[] = {"intercept_core"};
        author = "headswe";
        version = "0.1";
        versionStr = "0.1.0";
        versionAr[] = {0,1,0};
    };
};

// Tells Intercept to load intercept/intercept_aar_x64.dll from this mod's folder.
class Intercept {
    class headswe {
        class intercept_aar {
            pluginName = "intercept_aar";
        };
    };
};
