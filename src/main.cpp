#include <intercept.hpp>

#include "recorder.hpp"

using namespace intercept;

namespace {
types::registered_sqf_function projectile_command;

// interceptAARProjectile [kind, projectile, ...] - called from the projectile event handlers added in SQF.
game_value projectile_event(game_state&, game_value_parameter args) {
    aar::instance().on_projectile_event(args);
    return {};
}
}  // namespace

int intercept::api_version() {  // required by Intercept
    return INTERCEPT_SDK_API_VERSION;
}

void intercept::register_interfaces() {}

void intercept::pre_start() {
    // SQF commands can only be registered here.
    projectile_command = client::host::register_sqf_command(
        "interceptAARProjectile", "Intercept AAR: projectile event", projectile_event, types::game_data_type::NOTHING,
        types::game_data_type::ARRAY);
}

void intercept::pre_init() { aar::instance().start(); }

void intercept::post_init() { aar::instance().attach_mission_handlers(); }

void intercept::on_frame() { aar::instance().on_frame(); }

void intercept::mission_ended() { aar::instance().stop("mission_ended"); }

void intercept::handle_unload() { aar::instance().stop("unload"); }
