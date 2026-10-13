#pragma once
// Cleans up the record text the SQF addon sends before it is written.
//
// The addon builds each record as JSON: strings come from `toJSON`, numbers
// from `toFixed`. This trims numbers ("12.50" -> "12.5"), replaces anything that
// is not valid JSON outside a string (nan, inf, ...) with 0, and splits the
// batch into one record per line.

#include <cstddef>
#include <cstdio>
#include <string>
#include <string_view>

namespace aar {

// callExtension passes every argument as SQF `str` of the value, so a string
// arrives wrapped in quotes with inner quotes doubled. Undoes that.
inline std::string unquote_sqf(std::string_view s) {
    if (s.size() < 2 || s.front() != '"' || s.back() != '"') return std::string(s);
    s = s.substr(1, s.size() - 2);
    std::string out;
    out.reserve(s.size());
    for (size_t i = 0; i < s.size(); ++i) {
        out += s[i];
        if (s[i] == '"' && i + 1 < s.size() && s[i + 1] == '"') ++i;
    }
    return out;
}

namespace detail {

inline bool is_json_number(std::string_view s) {
    size_t i = 0, n = s.size();
    if (i < n && s[i] == '-') ++i;
    if (i >= n || s[i] < '0' || s[i] > '9') return false;
    if (s[i] == '0') {
        ++i;
    } else {
        while (i < n && s[i] >= '0' && s[i] <= '9') ++i;
    }
    if (i < n && s[i] == '.') {
        ++i;
        size_t start = i;
        while (i < n && s[i] >= '0' && s[i] <= '9') ++i;
        if (i == start) return false;
    }
    if (i < n && (s[i] == 'e' || s[i] == 'E')) {
        ++i;
        if (i < n && (s[i] == '+' || s[i] == '-')) ++i;
        size_t start = i;
        while (i < n && s[i] >= '0' && s[i] <= '9') ++i;
        if (i == start) return false;
    }
    return i == n;
}

// "12.50" -> "12.5", "3.00" -> "3", "-0.00" -> "0"; anything that is not a number -> "0".
inline void append_number(std::string& out, std::string_view tok) {
    std::string t(tok);
    if (t.find('.') != std::string::npos && t.find_first_of("eE") == std::string::npos) {
        while (!t.empty() && t.back() == '0') t.pop_back();
        if (!t.empty() && t.back() == '.') t.pop_back();
    }
    if (t == "-0" || !is_json_number(t)) t = "0";
    out += t;
}

inline bool is_token_char(char c) {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '.' || c == '-' ||
           c == '+' || c == '#' || c == '_';
}

}  // namespace detail

// Converts a block of newline-separated records and appends them to out, one
// JSON object per line, each ending in '\n'.
inline void sqf_records_to_json(std::string_view in, std::string& out) {
    std::string line;
    bool in_str = false;
    auto end_line = [&] {
        if (!line.empty()) {
            out += line;
            out += '\n';
            line.clear();
        }
    };
    for (size_t i = 0; i < in.size(); ++i) {
        char c = in[i];
        if (in_str) {
            unsigned char u = static_cast<unsigned char>(c);
            if (c == '\\' && i + 1 < in.size()) {
                line += c;  // keep toJSON's escape sequence as it is
                line += in[++i];
            } else if (c == '"') {
                line += '"';
                in_str = false;
            } else if (u < 0x20) {  // toJSON escapes these; stay valid if one slips through
                char esc[8];
                std::snprintf(esc, sizeof(esc), "\\u%04x", u);
                line += esc;
            } else {
                line += c;
            }
            continue;
        }
        if (c == '"') {
            line += '"';
            in_str = true;
        } else if (c == '\n' || c == '\r') {
            end_line();
        } else if (detail::is_token_char(c)) {
            size_t start = i;
            while (i + 1 < in.size() && detail::is_token_char(in[i + 1])) ++i;
            std::string_view tok = in.substr(start, i - start + 1);
            if (tok == "true" || tok == "false" || tok == "null") {
                line += tok;
            } else {
                detail::append_number(line, tok);
            }
        } else if (c != ' ' && c != '\t') {
            line += c;
        }
    }
    if (in_str) line += '"';  // unterminated string; keep the line parseable
    end_line();
}

}  // namespace aar
