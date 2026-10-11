#pragma once
// Minimal builder for one-line JSON objects. Records are flat objects whose
// values are numbers, strings, bools or simple arrays, so a full JSON library
// is not needed.

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <string>
#include <string_view>

namespace aar {

class json_line {
public:
    explicit json_line(std::string_view type, float time) {
        buf_.reserve(128);
        buf_ += '{';
        field("type", type);
        field("t", time);
    }

    json_line& field(std::string_view key, std::string_view value) {
        key_(key);
        str_(value);
        return *this;
    }
    json_line& field(std::string_view key, const char* value) { return field(key, std::string_view(value ? value : "")); }
    json_line& field(std::string_view key, const std::string& value) { return field(key, std::string_view(value)); }

    json_line& field(std::string_view key, bool value) {
        key_(key);
        buf_ += value ? "true" : "false";
        return *this;
    }
    json_line& field(std::string_view key, int value) {
        key_(key);
        buf_ += std::to_string(value);
        return *this;
    }
    json_line& field(std::string_view key, float value) {
        key_(key);
        num(buf_, value);
        return *this;
    }

    // [x,y,z] rounded to centimetres.
    json_line& field_pos(std::string_view key, float x, float y, float z) {
        key_(key);
        buf_ += '[';
        num(buf_, x);
        buf_ += ',';
        num(buf_, y);
        buf_ += ',';
        num(buf_, z);
        buf_ += ']';
        return *this;
    }

    // Append pre-rendered JSON as the value of key (used for snapshot arrays).
    json_line& raw(std::string_view key, std::string_view json) {
        key_(key);
        buf_ += json;
        return *this;
    }

    std::string finish() {
        buf_ += "}\n";
        return std::move(buf_);
    }

    // Writes a number with at most two decimals and no trailing zeros. NaN/inf become 0.
    static void num(std::string& out, float v) {
        if (!std::isfinite(v)) v = 0.f;
        char tmp[32];
        int n = std::snprintf(tmp, sizeof(tmp), "%.2f", static_cast<double>(v));
        if (n <= 0) {
            out += '0';
            return;
        }
        while (n > 1 && tmp[n - 1] == '0') --n;
        if (tmp[n - 1] == '.') --n;
        if (n == 2 && tmp[0] == '-' && tmp[1] == '0') {  // "-0"
            out += '0';
            return;
        }
        out.append(tmp, static_cast<size_t>(n));
    }

    static void str(std::string& out, std::string_view s) {
        out += '"';
        for (unsigned char c : s) {
            switch (c) {
                case '"': out += "\\\""; break;
                case '\\': out += "\\\\"; break;
                case '\n': out += "\\n"; break;
                case '\r': out += "\\r"; break;
                case '\t': out += "\\t"; break;
                default:
                    if (c < 0x20) {
                        char esc[8];
                        std::snprintf(esc, sizeof(esc), "\\u%04x", c);
                        out += esc;
                    } else {
                        out += static_cast<char>(c);
                    }
            }
        }
        out += '"';
    }

private:
    void key_(std::string_view key) {
        if (buf_.size() > 1) buf_ += ',';
        str(buf_, key);
        buf_ += ':';
    }
    void str_(std::string_view s) { str(buf_, s); }

    std::string buf_;
};

}  // namespace aar
