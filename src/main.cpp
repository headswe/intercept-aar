#include <intercept.hpp>

#include "recorder.hpp"

int intercept::api_version() {  // required by Intercept
    return INTERCEPT_SDK_API_VERSION;
}

void intercept::register_interfaces() {}

void intercept::pre_init() { aar::instance().start(); }

void intercept::post_init() { aar::instance().attach_mission_handlers(); }

void intercept::on_frame() { aar::instance().on_frame(); }

void intercept::mission_ended() { aar::instance().stop("mission_ended"); }

void intercept::handle_unload() { aar::instance().stop("unload"); }
