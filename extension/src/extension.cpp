// Arma 3 callExtension entry points for the AAR recorder.
//
//   "arma_aar" callExtension ["open", [missionName, worldName]]  -> ["<file path>","<started utc>"]
//   "arma_aar" callExtension ["write", [records]]                 -> appends records (see sqf_json.hpp)
//   "arma_aar" callExtension ["close", []]
//   "arma_aar" callExtension "version"
//
// All calls come from the game thread; the file is written on a background thread.

#include <cstdlib>
#include <cstring>
#include <ctime>
#include <filesystem>
#include <string>
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

}  // namespace

void AAR_CALL RVExtensionVersion(char* output, unsigned int output_size) { set_output(output, output_size, AAR_VERSION); }

void AAR_CALL RVExtension(char* output, unsigned int output_size, const char* function) {
    set_output(output, output_size, std::string_view(function) == "version" ? AAR_VERSION : "");
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
        return ok;
    }
    if (fn == "close") {
        writer().close();
        return ok;
    }
    return unknown_function;
}
