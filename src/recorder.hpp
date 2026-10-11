#pragma once
// Records a mission for After Action Review: entity state snapshots plus
// gameplay events, written as line-delimited JSON (one record per line).

#include <intercept.hpp>

#include <cstdint>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

#include "async_writer.hpp"

namespace aar {

using intercept::client::EHIdentifierHandle;
using intercept::types::object;

struct settings {
    bool enabled = true;
    float interval = 1.0f;            // seconds of mission time between snapshots
    float keyframe_interval = 60.0f;  // full (non-delta) snapshot every N seconds
    bool log_projectiles = true;      // shot, hit and impact records; large in big firefights
    bool log_hits = true;
    bool log_markers = true;
    std::string output_dir;           // empty = <arma working dir>/aar
};

class recorder {
public:
    // Call from pre_init. Reads settings and opens the output file (server only).
    void start();
    // Call from post_init. Mission event handlers need a running mission.
    void attach_mission_handlers();
    // Call every frame; takes a snapshot whenever the interval has elapsed.
    void on_frame();
    // Called by the interceptAARProjectile SQF command: [kind, projectile, ...].
    void on_projectile_event(const intercept::types::game_value& args);
    // Call when the mission ends or the plugin unloads.
    void stop(std::string_view reason);

    bool active() const { return active_; }

private:
    struct tracked {
        object obj;
        std::string kind;
        std::string group;
        std::string side;
        std::string uid;
        float x = 0, y = 0, z = 0, dir = 0, damage = 0;
        int vehicle = 0;
        bool alive = true;
        bool has_state = false;
        std::vector<EHIdentifierHandle> handlers;
    };

    // Returns the AAR id of obj, registering it if it is new. 0 for null or ignored objects.
    int id_of(const object& obj);
    // Returns the id without registering: 0 unknown, -1 ignored.
    int known_id(const object& obj) const;
    int register_entity(const object& obj);
    void attach_object_handlers(int id, tracked& t);
    void discover();
    void snapshot(bool keyframe);
    void emit(std::string line);
    float now() const;

    settings settings_;
    async_writer out_;
    bool active_ = false;
    int next_id_ = 1;
    int next_projectile_id_ = 1;
    int projectile_eh_ = -1;
    float last_snapshot_ = -1e9f;
    float last_keyframe_ = -1e9f;
    std::unordered_map<int, tracked> entities_;
    struct projectile_state {
        int shooter = 0;
        std::vector<int> hit_targets;  // entities already reported in proj_hit / proj_splash
    };
    std::unordered_map<int, projectile_state> projectiles_;  // in flight; erased at proj_end
    std::vector<EHIdentifierHandle> mission_handlers_;
    std::string path_;
    std::string pending_stop_;
};

recorder& instance();

}  // namespace aar
