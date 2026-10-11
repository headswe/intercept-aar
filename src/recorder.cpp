#include "recorder.hpp"

#include <chrono>
#include <cmath>
#include <cstdlib>
#include <ctime>
#include <filesystem>
#include <unordered_set>

#include "json_line.hpp"

using namespace intercept;
using namespace intercept::client;
using intercept::types::r_string;

namespace aar {

namespace {

constexpr std::string_view id_var = "aar_id";  // object variable holding our entity id; -1 = ignored
constexpr int format_version = 1;

std::string to_std(std::string_view s) { return std::string(s); }

std::string side_name(const types::side& s) {
    return to_std(sqf::str(s));  // WEST, EAST, GUER, CIV, LOGIC, ...
}

std::string group_name(const object& obj) {
    auto grp = sqf::group_get(obj);
    if (grp.is_null()) return {};
    return to_std(sqf::group_id(grp));
}

// Classifies an object, or returns empty for things we do not record
// (weapon holders, ammo crates, logic objects and so on).
std::string classify(const object& obj) {
    if (sqf::is_kind_of(obj, "CAManBase")) return "unit";
    if (sqf::is_kind_of(obj, "StaticWeapon")) return "static";
    if (sqf::is_kind_of(obj, "Tank")) return "tank";
    if (sqf::is_kind_of(obj, "Car")) return "car";
    if (sqf::is_kind_of(obj, "Helicopter")) return "heli";
    if (sqf::is_kind_of(obj, "Plane")) return "plane";
    if (sqf::is_kind_of(obj, "Ship")) return "ship";
    if (sqf::is_kind_of(obj, "LandVehicle")) return "vehicle";
    if (sqf::is_kind_of(obj, "Air")) return "air";
    return {};
}

std::string display_name(std::string_view class_name) {
    sqf::config_entry cfg = sqf::config_entry(sqf::config_file()) >> "CfgVehicles" >> class_name >> "displayName";
    return to_std(sqf::get_text(cfg));
}

std::string sanitize(std::string_view s) {
    std::string out;
    for (char c : s) {
        bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.';
        out += ok ? c : '_';
    }
    return out.empty() ? "mission" : out;
}

std::string utc_stamp(const char* fmt) {
    std::time_t now = std::time(nullptr);
    std::tm tm{};
#ifdef _WIN32
    gmtime_s(&tm, &now);
#else
    gmtime_r(&now, &tm);
#endif
    char buf[32];
    std::strftime(buf, sizeof(buf), fmt, &tm);
    return buf;
}

// Mission config overrides: class InterceptAAR { interval = 0.5; logFired = 0; ... }; in description.ext
settings read_settings() {
    settings s;
    sqf::config_entry root = sqf::config_entry(sqf::mission_config_file()) >> "InterceptAAR";
    auto num = [&](std::string_view key, float fallback) {
        sqf::config_entry e = root >> key;
        return sqf::is_number(e) ? sqf::get_number(e) : fallback;
    };
    s.enabled = num("enabled", 1.f) != 0.f;
    s.interval = std::max(0.1f, num("interval", s.interval));
    s.keyframe_interval = std::max(s.interval, num("keyframeInterval", s.keyframe_interval));
    s.log_fired = num("logFired", 1.f) != 0.f;
    s.log_hits = num("logHits", 1.f) != 0.f;
    s.log_markers = num("logMarkers", 1.f) != 0.f;
    if (const char* dir = std::getenv("AAR_OUTPUT_DIR"); dir && *dir) s.output_dir = dir;
    return s;
}

const char* role_name(get_in_position p) {
    switch (p) {
        case get_in_position::driver: return "driver";
        case get_in_position::gunner: return "gunner";
        default: return "cargo";
    }
}

void log_rpt(const std::string& msg) { sqf::diag_log("[InterceptAAR] " + msg); }

}  // namespace

recorder& instance() {
    static recorder r;
    return r;
}

float recorder::now() const { return sqf::time(); }

void recorder::emit(std::string line) { out_.write(std::move(line)); }

void recorder::start() {
    stop("restart");
    // Only the server (or a singleplayer / hosted game) records; clients and headless clients do nothing.
    if (!sqf::is_server()) return;

    settings_ = read_settings();
    if (!settings_.enabled) {
        log_rpt("disabled by mission config");
        return;
    }

    namespace fs = std::filesystem;
    fs::path dir = settings_.output_dir.empty() ? fs::current_path() / "aar" : fs::path(settings_.output_dir);
    std::error_code ec;
    fs::create_directories(dir, ec);

    std::string mission = to_std(sqf::mission_name());
    std::string world = to_std(sqf::world_name());
    path_ = (dir / (utc_stamp("%Y%m%d-%H%M%S") + "_" + sanitize(mission) + "_" + sanitize(world) + ".jsonl")).string();
    if (!out_.open(path_)) {
        log_rpt("could not open " + path_);
        return;
    }

    active_ = true;
    next_id_ = 1;
    last_snapshot_ = last_keyframe_ = -1e9f;
    entities_.clear();

    emit(json_line("header", now())
             .field("version", format_version)
             .field("mission", mission)
             .field("world", world)
             .field("started_utc", utc_stamp("%Y-%m-%dT%H:%M:%SZ"))
             .field("interval", settings_.interval)
             .field("keyframe_interval", settings_.keyframe_interval)
             .field("multiplayer", sqf::is_multiplayer())
             .finish());
    log_rpt("recording to " + path_);
}

void recorder::attach_mission_handlers() {
    if (!active_) return;
    mission_handlers_.clear();

    mission_handlers_.push_back(addMissionEventHandler<eventhandlers_mission::EntityKilled>(
        [this](object killed, object killer, object instigator, bool) {
            int victim = id_of(killed);
            if (!victim) return;
            auto pos = sqf::get_pos_asl(killed);
            emit(json_line("killed", now())
                     .field("victim", victim)
                     .field("killer", id_of(killer))
                     .field("instigator", id_of(instigator))
                     .field_pos("pos", pos.x, pos.y, pos.z)
                     .finish());
        }));

    mission_handlers_.push_back(addMissionEventHandler<eventhandlers_mission::EntityRespawned>(
        [this](object new_entity, object old_entity) {
            emit(json_line("respawn", now())
                     .field("new", id_of(new_entity))
                     .field("old", id_of(old_entity))
                     .finish());
        }));

    mission_handlers_.push_back(addMissionEventHandler<eventhandlers_mission::PlayerConnected>(
        [this](int, r_string uid, r_string name, bool jip, int owner) {
            emit(json_line("connected", now())
                     .field("uid", std::string_view(uid))
                     .field("name", std::string_view(name))
                     .field("jip", jip)
                     .field("owner", owner)
                     .finish());
        }));

    mission_handlers_.push_back(addMissionEventHandler<eventhandlers_mission::PlayerDisconnected>(
        [this](int, r_string uid, r_string name, bool jip, int owner) {
            emit(json_line("disconnected", now())
                     .field("uid", std::string_view(uid))
                     .field("name", std::string_view(name))
                     .field("jip", jip)
                     .field("owner", owner)
                     .finish());
        }));

    mission_handlers_.push_back(addMissionEventHandler<eventhandlers_mission::MPEnded>(
        [this]() { pending_stop_ = "mp_ended"; }));
    mission_handlers_.push_back(addMissionEventHandler<eventhandlers_mission::Ended>(
        [this](r_string end_type) { pending_stop_ = "ended:" + to_std(end_type); }));

    if (settings_.log_markers) {
        mission_handlers_.push_back(addMissionEventHandler<eventhandlers_mission::MarkerCreated>(
            [this](r_string marker, int channel, object owner, bool) {
                auto pos = sqf::get_marker_pos(std::string(std::string_view(marker)));
                emit(json_line("marker_created", now())
                         .field("marker", std::string_view(marker))
                         .field("channel", channel)
                         .field("owner", id_of(owner))
                         .field("text", sqf::marker_text(std::string(std::string_view(marker))))
                         .field("markerType", sqf::marker_type(std::string(std::string_view(marker))))
                         .field("color", sqf::marker_color(std::string(std::string_view(marker))))
                         .field_pos("pos", pos.x, pos.y, pos.z)
                         .finish());
            }));
        mission_handlers_.push_back(addMissionEventHandler<eventhandlers_mission::MarkerUpdated>(
            [this](r_string marker, bool) {
                auto pos = sqf::get_marker_pos(std::string(std::string_view(marker)));
                emit(json_line("marker_updated", now())
                         .field("marker", std::string_view(marker))
                         .field("text", sqf::marker_text(std::string(std::string_view(marker))))
                         .field_pos("pos", pos.x, pos.y, pos.z)
                         .finish());
            }));
        mission_handlers_.push_back(addMissionEventHandler<eventhandlers_mission::MarkerDeleted>(
            [this](r_string marker, bool) {
                emit(json_line("marker_deleted", now()).field("marker", std::string_view(marker)).finish());
            }));
    }
}

int recorder::known_id(const object& obj) const {
    if (obj.is_null()) return 0;
    float id = sqf::get_variable(obj, std::string(id_var), game_value(0.f));
    return id > 0.f ? static_cast<int>(id) : static_cast<int>(id < 0.f ? -1 : 0);
}

int recorder::id_of(const object& obj) {
    if (obj.is_null()) return 0;
    int id = known_id(obj);
    if (id < 0) return 0;  // ignored object
    if (id > 0) return id;
    return register_entity(obj);
}

int recorder::register_entity(const object& obj) {
    std::string kind = classify(obj);
    if (kind.empty()) {
        sqf::set_variable(obj, std::string(id_var), game_value(-1.f));
        return 0;
    }

    int id = next_id_++;
    sqf::set_variable(obj, std::string(id_var), game_value(static_cast<float>(id)));

    tracked& t = entities_[id];
    t.obj = obj;
    t.kind = kind;
    t.side = side_name(sqf::get_side(obj));
    t.group = kind == "unit" ? group_name(obj) : std::string();
    t.uid = sqf::is_player(obj) ? to_std(sqf::get_player_uid(obj)) : std::string();

    std::string class_name = to_std(sqf::type_of(obj));
    json_line line("entity", now());
    line.field("id", id)
        .field("kind", kind)
        .field("class", class_name)
        .field("display", display_name(class_name))
        .field("side", t.side);
    if (kind == "unit") {
        line.field("name", to_std(sqf::name(obj)))
            .field("group", t.group)
            .field("player", !t.uid.empty())
            .field("uid", t.uid);
    }
    emit(line.finish());

    attach_object_handlers(id, t);
    return id;
}

void recorder::attach_object_handlers(int id, tracked& t) {
    if (settings_.log_fired) {
        t.handlers.push_back(addEventHandler<eventhandlers_object::Fired>(
            t.obj, [this, id](object unit, r_string weapon, r_string muzzle, r_string, r_string ammo, r_string, object, object gunner) {
                auto pos = sqf::get_pos_asl(unit);
                json_line line("fired", now());
                line.field("unit", id);
                int gunner_id = id_of(gunner);
                if (gunner_id && gunner_id != id) line.field("gunner", gunner_id);
                emit(line.field("weapon", std::string_view(weapon))
                         .field("muzzle", std::string_view(muzzle))
                         .field("ammo", std::string_view(ammo))
                         .field_pos("pos", pos.x, pos.y, pos.z)
                         .finish());
            }));
    }

    if (settings_.log_hits) {
        // Hit only fires where the unit is local: AI on the server, not remote players.
        t.handlers.push_back(addEventHandler<eventhandlers_object::Hit>(
            t.obj, [this, id](object, object caused_by, float damage, object instigator) {
                emit(json_line("hit", now())
                         .field("unit", id)
                         .field("source", id_of(caused_by))
                         .field("instigator", id_of(instigator))
                         .field("damage", damage)
                         .finish());
            }));
    }

    if (t.kind != "unit") {
        t.handlers.push_back(addEventHandler<eventhandlers_object::GetIn>(
            t.obj, [this, id](object, get_in_position position, object unit, types::rv_turret_path) {
                emit(json_line("get_in", now()).field("vehicle", id).field("unit", id_of(unit)).field("role", role_name(position)).finish());
            }));
        t.handlers.push_back(addEventHandler<eventhandlers_object::GetOut>(
            t.obj, [this, id](object, get_in_position position, object unit, types::rv_turret_path) {
                emit(json_line("get_out", now()).field("vehicle", id).field("unit", id_of(unit)).field("role", role_name(position)).finish());
            }));
    }
}

void recorder::discover() {
    for (auto& unit : sqf::all_units()) id_of(unit);
    for (auto& veh : sqf::vehicles()) id_of(veh);
}

void recorder::snapshot(bool keyframe) {
    std::string rows;
    rows.reserve(entities_.size() * 48);
    rows += '[';
    bool first = true;
    std::vector<int> deleted;

    for (auto& [id, t] : entities_) {
        if (t.obj.is_null()) {
            deleted.push_back(id);
            continue;
        }

        auto pos = sqf::get_pos_asl(t.obj);
        float dir = sqf::get_dir(t.obj);
        bool alive = sqf::alive(t.obj);
        float damage = sqf::damage(t.obj);
        int vehicle = 0;
        if (t.kind == "unit") {
            object veh = sqf::vehicle(t.obj);
            // Lookup only: registering here would modify entities_ while we iterate it.
            if (!(veh == t.obj)) vehicle = std::max(0, known_id(veh));
        }

        // Group, side and player changes are rare, so they are events rather than snapshot columns.
        if (t.kind == "unit" && alive) {
            std::string group = group_name(t.obj);
            std::string side = side_name(sqf::get_side(t.obj));
            if (group != t.group || side != t.side) {
                t.group = group;
                t.side = side;
                emit(json_line("group", now()).field("unit", id).field("group", group).field("side", side).finish());
            }
            std::string uid = sqf::is_player(t.obj) ? to_std(sqf::get_player_uid(t.obj)) : std::string();
            if (uid != t.uid) {
                t.uid = uid;
                emit(json_line("player", now()).field("unit", id).field("uid", uid).field("name", to_std(sqf::name(t.obj))).finish());
            }
        }

        bool changed = !t.has_state || keyframe || alive != t.alive || vehicle != t.vehicle ||
                       std::fabs(pos.x - t.x) > 0.1f || std::fabs(pos.y - t.y) > 0.1f || std::fabs(pos.z - t.z) > 0.1f ||
                       std::fabs(dir - t.dir) > 1.0f || std::fabs(damage - t.damage) > 0.01f;
        if (!changed) continue;

        t.x = pos.x;
        t.y = pos.y;
        t.z = pos.z;
        t.dir = dir;
        t.alive = alive;
        t.damage = damage;
        t.vehicle = vehicle;
        t.has_state = true;

        if (!first) rows += ',';
        first = false;
        // [id, x, y, z, dir, alive, damage, vehicle_id]
        rows += '[';
        rows += std::to_string(id);
        rows += ',';
        json_line::num(rows, pos.x);
        rows += ',';
        json_line::num(rows, pos.y);
        rows += ',';
        json_line::num(rows, pos.z);
        rows += ',';
        rows += std::to_string(static_cast<int>(std::lround(dir)) % 360);
        rows += alive ? ",1," : ",0,";
        json_line::num(rows, damage);
        rows += ',';
        rows += std::to_string(vehicle);
        rows += ']';
    }
    rows += ']';

    emit(json_line("snap", now()).field("key", keyframe).raw("e", rows).finish());

    for (int id : deleted) {
        emit(json_line("deleted", now()).field("id", id).finish());
        entities_.erase(id);
    }
}

void recorder::on_frame() {
    if (!active_) return;
    if (!pending_stop_.empty()) {
        // Deferred from the Ended/MPEnded handlers: stopping clears those handlers, which must not happen inside them.
        stop(pending_stop_);
        return;
    }
    float t = now();
    if (t - last_snapshot_ < settings_.interval) return;
    last_snapshot_ = t;
    bool keyframe = t - last_keyframe_ >= settings_.keyframe_interval;
    if (keyframe) last_keyframe_ = t;
    discover();
    snapshot(keyframe);
}

void recorder::stop(std::string_view reason) {
    if (!active_) return;
    active_ = false;
    if (!pending_stop_.empty()) reason = pending_stop_;
    emit(json_line("end", now()).field("reason", reason).field("entities", next_id_ - 1).finish());
    mission_handlers_.clear();
    entities_.clear();  // drops the object event handlers
    out_.close();
    log_rpt("stopped (" + std::string(reason) + "), wrote " + path_);
    pending_stop_.clear();
}

}  // namespace aar
