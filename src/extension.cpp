// Arma 3 callExtension entry points for the AAR recorder.
//
//   "arma_aar" callExtension ["open", [missionName, worldName]]  -> ["<file path>","<started utc>"]
//   "arma_aar" callExtension "tick"                               -> starts a timer on the game thread
//   "arma_aar" callExtension ["write", [records]]                 -> appends records (see sqf_json.hpp); returns the
//                                                                    microseconds since "tick", if one is pending
//   "arma_aar" callExtension ["close", []]
//   "arma_aar" callExtension "version"
//
// Game data for the viewer (aar_fnc_gameData, see gamedata.hpp):
//   "arma_aar" callExtension ["gd_begin", []]             -> "ok" (starts collecting), or "busy" while an export runs
//   "arma_aar" callExtension ["gd_add", [table, json]]     -> adds a JSON object of rows to a table of aar-cfg.json
//   "arma_aar" callExtension ["gd_done", [header, textures, mod folders]] -> writes aar-cfg.json, the PNGs and
//                                                            aar-icons.json on a background thread
//   "arma_aar" callExtension "gd_status"                   -> "busy", or how the last export went
//
// All calls come from the game thread; the files are written on background threads.

#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <filesystem>
#include <mutex>
#include <string>
#include <string_view>
#include <thread>

#include "async_writer.hpp"
#include "gamedata.hpp"
#include "sqf_json.hpp"

#ifdef _WIN32
#define AAR_EXPORT __declspec(dllexport)
#define AAR_CALL __stdcall
#else
#define AAR_EXPORT __attribute__((visibility("default")))
#define AAR_CALL
#endif

#ifndef AAR_VERSION
#define AAR_VERSION "0.1.0"
#endif

extern "C" {
AAR_EXPORT void AAR_CALL RVExtensionVersion(char* output, unsigned int output_size);
AAR_EXPORT void AAR_CALL RVExtension(char* output, unsigned int output_size, const char* function);
AAR_EXPORT int AAR_CALL RVExtensionArgs(char* output, unsigned int output_size, const char* function, const char** argv,
                                        unsigned int argc);
}

namespace {

enum result_code { ok = 0, error = 1, unknown_function = 2 };

// Intentionally never destroyed: joining a thread from a DLL's static destructor can deadlock
// on process exit. The writer flushes every second, so an unclean exit loses at most that.
aar::async_writer& writer() {
    static auto* w = new aar::async_writer();
    return *w;
}

// Measures the recorder's own work in a frame: "tick" at the start, the next "write" reads it.
std::chrono::steady_clock::time_point tick_time;
bool tick_pending = false;

void set_output(char* output, unsigned int size, std::string_view text) {
    if (size == 0) return;
    size_t n = text.size() < size - 1 ? text.size() : size - 1;
    std::memcpy(output, text.data(), n);
    output[n] = '\0';
}

std::string sqf_string(std::string_view s) {
    std::string out = "\"";
    for (char c : s) {
        out += c;
        if (c == '"') out += '"';
    }
    return out + "\"";
}

std::string sanitize(std::string_view s) {
    std::string out;
    for (char c : s) {
        bool keep = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.';
        out += keep ? c : '_';
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

std::filesystem::path output_dir() {
    namespace fs = std::filesystem;
    std::error_code ec;
    const char* env = std::getenv("AAR_OUTPUT_DIR");
    fs::path dir = env && *env ? fs::path(env) : fs::current_path(ec) / "aar";
    fs::create_directories(dir, ec);
    return dir;
}

int open_file(char* output, unsigned int size, const char** argv, unsigned int argc) {
    writer().close();
    std::string mission = argc > 0 ? aar::unquote_sqf(argv[0]) : "";
    std::string world = argc > 1 ? aar::unquote_sqf(argv[1]) : "";
    std::filesystem::path dir = output_dir();

    std::string path = (dir / (utc_stamp("%Y%m%d-%H%M%S") + "_" + sanitize(mission) + "_" + sanitize(world) + ".jsonl")).string();
    if (!writer().open(path)) {
        set_output(output, size, "could not open " + path);
        return error;
    }
    set_output(output, size, "[" + sqf_string(path) + "," + sqf_string(utc_stamp("%Y-%m-%dT%H:%M:%SZ")) + "]");
    return ok;
}

// ---------- game data ----------

// The export being collected on the game thread, then handed to a detached thread that owns it.
// Never destroyed, like the writer.
aar::gamedata::job& gd_job() {
    static auto* j = new aar::gamedata::job();
    return *j;
}
std::atomic<bool> gd_busy{false};
std::mutex gd_mutex;
std::string gd_result = "no export yet";

int gamedata(std::string_view fn, char* output, unsigned int size, const char** argv, unsigned int argc) {
    namespace fs = std::filesystem;
    auto arg = [&](unsigned int i) { return i < argc ? aar::unquote_sqf(argv[i]) : std::string(); };
    if (gd_busy) {
        set_output(output, size, "busy");
        return fn == "gd_begin" ? ok : error;
    }
    if (fn == "gd_begin") {
        gd_job() = aar::gamedata::job();
        gd_job().dir = output_dir();
        set_output(output, size, "ok");
        return ok;
    }
    if (fn == "gd_add") {
        std::string json = arg(1);
        std::string_view members = aar::gamedata::json_members(json);
        if (members.empty()) return ok;
        std::string& table = gd_job().tables[arg(0)];
        if (!table.empty()) table += ',';
        table += members;
        return ok;
    }
    if (fn == "gd_done") {
        aar::gamedata::job j = std::move(gd_job());
        gd_job() = aar::gamedata::job();
        if (j.dir.empty()) {
            set_output(output, size, "no gd_begin before gd_done");
            return error;
        }
        j.header = arg(0);
        j.textures = aar::gamedata::json_strings(arg(1));
        // The game's own PBOs, then each loaded mod's folder (relative ones are under the game folder).
        std::error_code ec;
        fs::path game = fs::current_path(ec);
        j.search.push_back(game / "Addons");
        for (const std::string& m : aar::gamedata::json_strings(arg(2))) {
            if (m.empty()) continue;
            fs::path p(m);
            j.search.push_back(p.is_absolute() ? p : game / p);
        }
        gd_busy = true;
        std::thread([j = std::move(j)]() {
            std::string result;
            try {
                result = aar::gamedata::run(j);
            } catch (const std::exception& e) {
                result = std::string("export failed: ") + e.what();
            }
            {
                std::lock_guard<std::mutex> lock(gd_mutex);
                gd_result = result;
            }
            gd_busy = false;
        }).detach();
        return ok;
    }
    return unknown_function;
}

}  // namespace

void AAR_CALL RVExtensionVersion(char* output, unsigned int output_size) { set_output(output, output_size, AAR_VERSION); }

void AAR_CALL RVExtension(char* output, unsigned int output_size, const char* function) {
    std::string_view fn(function);
    if (fn == "tick") {
        tick_time = std::chrono::steady_clock::now();
        tick_pending = true;
        set_output(output, output_size, "");
        return;
    }
    if (fn == "gd_status") {
        if (gd_busy) {
            set_output(output, output_size, "busy");
        } else {
            std::lock_guard<std::mutex> lock(gd_mutex);
            set_output(output, output_size, gd_result);
        }
        return;
    }
    set_output(output, output_size, fn == "version" ? AAR_VERSION : "");
}

int AAR_CALL RVExtensionArgs(char* output, unsigned int output_size, const char* function, const char** argv, unsigned int argc) {
    std::string_view fn(function);
    set_output(output, output_size, "");
    if (fn == "open") return open_file(output, output_size, argv, argc);
    if (fn == "write") {
        if (!writer().is_open()) {
            set_output(output, output_size, "not recording");
            return error;
        }
        std::string json;
        for (unsigned int i = 0; i < argc; ++i) aar::sqf_records_to_json(aar::unquote_sqf(argv[i]), json);
        writer().write(std::move(json));
        if (tick_pending) {
            tick_pending = false;
            auto us = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - tick_time).count();
            set_output(output, output_size, std::to_string(us));
        }
        return ok;
    }
    if (fn.substr(0, 3) == "gd_") return gamedata(fn, output, output_size, argv, argc);
    if (fn == "close") {
        writer().close();
        return ok;
    }
    return unknown_function;
}
