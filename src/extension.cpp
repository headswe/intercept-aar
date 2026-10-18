// Arma 3 callExtension entry points for the AAR recorder.
//
//   "arma_aar" callExtension ["open", [missionName, worldName]]  -> ["<file path>","<started utc>"]
//   "arma_aar" callExtension "tick"                               -> starts a timer on the game thread
//   "arma_aar" callExtension ["write", [records]]                 -> appends records (see sqf_json.hpp); returns the
//                                                                    microseconds since "tick", if one is pending
//   "arma_aar" callExtension ["close", []]
//   "arma_aar" callExtension "netq"                               -> ["rx_queue","tx_queue","drops"] summed over the game's
//                                                                    UDP sockets (Linux only, "" elsewhere)
//   "arma_aar" callExtension "version"
//
// All calls come from the game thread; the file is written on a background thread.

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <unordered_set>
#include <string_view>

#include "async_writer.hpp"
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

int open_file(char* output, unsigned int size, const char** argv, unsigned int argc) {
    namespace fs = std::filesystem;
    writer().close();
    std::string mission = argc > 0 ? aar::unquote_sqf(argv[0]) : "";
    std::string world = argc > 1 ? aar::unquote_sqf(argv[1]) : "";

    std::error_code ec;
    const char* env = std::getenv("AAR_OUTPUT_DIR");
    fs::path dir = env && *env ? fs::path(env) : fs::current_path(ec) / "aar";
    fs::create_directories(dir, ec);

    std::string path = (dir / (utc_stamp("%Y%m%d-%H%M%S") + "_" + sanitize(mission) + "_" + sanitize(world) + ".jsonl")).string();
    if (!writer().open(path)) {
        set_output(output, size, "could not open " + path);
        return error;
    }
    set_output(output, size, "[" + sqf_string(path) + "," + sqf_string(utc_stamp("%Y-%m-%dT%H:%M:%SZ")) + "]");
    return ok;
}

// The operating system's queues for the game's own UDP sockets: bytes received but not yet read by
// the game, bytes waiting to be sent, and datagrams dropped because the receive buffer was full
// (cumulative). Read from /proc, so Linux only. Sockets are matched by inode against this
// process's open file descriptors, so other processes on the host are left out.
std::string udp_queues() {
#ifdef __linux__
    namespace fs = std::filesystem;
    std::unordered_set<unsigned long> inodes;
    std::error_code ec;
    for (fs::directory_iterator it("/proc/self/fd", ec), end; !ec && it != end; it.increment(ec)) {
        std::string target = fs::read_symlink(it->path(), ec).string();
        if (ec) { ec.clear(); continue; }
        if (target.rfind("socket:[", 0) == 0) inodes.insert(std::strtoul(target.c_str() + 8, nullptr, 10));
    }
    unsigned long long rx = 0, tx = 0, drops = 0;
    int sockets = 0;
    for (const char* table : {"/proc/self/net/udp", "/proc/self/net/udp6"}) {
        std::ifstream in(table);
        std::string line;
        std::getline(in, line);  // header
        while (std::getline(in, line)) {
            // sl local rem st tx_queue:rx_queue tr:when retrnsmt uid timeout inode ref pointer drops
            std::istringstream f(line);
            std::string col[13];
            int n = 0;
            while (n < 13 && f >> col[n]) ++n;
            if (n < 13 || !inodes.count(std::strtoul(col[9].c_str(), nullptr, 10))) continue;
            auto colon = col[4].find(':');
            if (colon == std::string::npos) continue;
            tx += std::strtoull(col[4].substr(0, colon).c_str(), nullptr, 16);
            rx += std::strtoull(col[4].substr(colon + 1).c_str(), nullptr, 16);
            drops += std::strtoull(col[12].c_str(), nullptr, 10);
            ++sockets;
        }
    }
    if (sockets == 0) return "";
    // Strings, since SQF would print counts over a million in scientific notation.
    return "[\"" + std::to_string(rx) + "\",\"" + std::to_string(tx) + "\",\"" + std::to_string(drops) + "\"]";
#else
    return "";
#endif
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
    if (fn == "netq") {
        set_output(output, output_size, udp_queues());
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
    if (fn == "close") {
        writer().close();
        return ok;
    }
    return unknown_function;
}
