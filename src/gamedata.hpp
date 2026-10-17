#pragma once
// Game data for the viewer: display names from the config (sent by aar_fnc_gameData) and the
// game's map icons, read from the .paa textures inside the server's PBOs and written as PNG.
// The same decoding as tools/export_icons.py.
//
// Writes, next to the recordings:
//   aar-cfg.json        names, pictures and icon classes (the format of tools/export_cfg.sqf)
//   aar-icons.json      {"format":"aar-icons","icons":{"<texture path>":"data:image/png;base64,..."}}
//   aar-gamedata.key    game version and mod list the files were made for

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <map>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace aar::gamedata {

using bytes = std::vector<uint8_t>;

// The key textures are looked up by: lower case, backslashes, no leading slash, ".paa" added.
inline std::string norm(std::string_view path) {
    std::string p;
    for (char c : path) p += c == '/' ? '\\' : (c >= 'A' && c <= 'Z') ? char(c - 'A' + 'a') : c;
    size_t start = p.find_first_not_of(" \\");
    if (start == std::string::npos) return "";
    p = p.substr(start);
    while (!p.empty() && p.back() == ' ') p.pop_back();
    size_t slash = p.rfind('\\');
    if (p.find('.', slash == std::string::npos ? 0 : slash) == std::string::npos) p += ".paa";
    return p;
}

// ---------- decompression ----------

// Bohemia's LZSS: flag bytes, literals, and 12-bit back references relative to the output end.
inline bytes lzss(const uint8_t* src, size_t n, size_t out_len) {
    bytes out;
    out.reserve(out_len);
    size_t i = 0;
    while (out.size() < out_len && i < n) {
        uint8_t flags = src[i++];
        for (int bit = 0; bit < 8 && out.size() < out_len && i < n; ++bit) {
            if (flags & (1 << bit)) {
                out.push_back(src[i++]);
            } else {
                if (i + 1 >= n) throw std::runtime_error("LZSS truncated");
                uint8_t b1 = src[i], b2 = src[i + 1];
                i += 2;
                long rpos = long(out.size()) - long(b1 | ((b2 & 0xF0) << 4));
                for (int k = 0; k < (b2 & 0x0F) + 3; ++k, ++rpos) out.push_back(rpos >= 0 ? out[size_t(rpos)] : 0x20);
            }
        }
    }
    out.resize(out_len);
    return out;
}

// LZO1X decompression (as in minilzo's lzo1x_decompress), used for DXT mipmaps.
inline bytes lzo1x(const uint8_t* src, size_t n, size_t out_len) {
    bytes out;
    out.reserve(out_len);
    size_t ip = 0;
    auto in = [&](size_t k) -> uint32_t {
        if (ip + k >= n) throw std::runtime_error("LZO input overrun");
        return src[ip + k];
    };
    auto literals = [&](size_t k) {
        if (ip + k > n) throw std::runtime_error("LZO input overrun");
        out.insert(out.end(), src + ip, src + ip + k);
        ip += k;
    };
    auto copy = [&](size_t back, size_t k) {
        if (back > out.size() || back == 0) throw std::runtime_error("LZO lookbehind overrun");
        size_t p = out.size() - back;
        for (size_t j = 0; j < k; ++j) out.push_back(out[p + j]);
        if (out.size() > out_len) throw std::runtime_error("LZO output overrun");
    };
    auto run = [&](uint32_t t, uint32_t extra) {
        if (t == 0) {
            while (in(0) == 0) { t += 255; ++ip; }
            t += extra + in(0);
            ++ip;
        }
        return t;
    };
    enum { loop, first_literal_run, match, match_done, match_next } state = loop;
    uint32_t t = 0;
    if (in(0) > 17) {
        t = in(0) - 17;
        ip = 1;
        if (t < 4) {
            state = match_next;
        } else {
            literals(t);
            state = first_literal_run;
        }
    }
    for (;;) {
        switch (state) {
        case loop:
            t = in(0); ++ip;
            if (t >= 16) { state = match; break; }
            literals(run(t, 15) + 3);
            state = first_literal_run;
            break;
        case first_literal_run:
            t = in(0); ++ip;
            if (t >= 16) { state = match; break; }
            copy(1 + 0x0800 + (t >> 2) + (in(0) << 2), 3);
            ++ip;
            state = match_done;
            break;
        case match:
            if (t >= 64) {
                size_t back = 1 + ((t >> 2) & 7) + (in(0) << 3);
                ++ip;
                copy(back, (t >> 5) + 1);
            } else if (t >= 32) {
                t = run(t & 31, 31);
                size_t back = 1 + (in(0) >> 2) + (in(1) << 6);
                ip += 2;
                copy(back, t + 2);
            } else if (t >= 16) {
                size_t back = size_t(t & 8) << 11;
                t = run(t & 7, 7);
                back += (in(0) >> 2) + (in(1) << 6);
                ip += 2;
                if (back == 0) {
                    if (out.size() != out_len) throw std::runtime_error("LZO output size mismatch");
                    return out;
                }
                copy(back + 0x4000, t + 2);
            } else {
                copy(1 + (t >> 2) + (in(0) << 2), 2);
                ++ip;
            }
            state = match_done;
            break;
        case match_done:
            if (ip < 2) throw std::runtime_error("LZO corrupt");
            t = src[ip - 2] & 3;
            state = t == 0 ? loop : match_next;
            break;
        case match_next:
            literals(t);
            t = in(0); ++ip;
            state = match;
            break;
        }
    }
}

// ---------- PAA ----------

struct image {
    int w = 0, h = 0;
    bytes rgba;
};

namespace detail {

inline uint16_t u16(const bytes& d, size_t p) {
    if (p + 2 > d.size()) throw std::runtime_error("PAA truncated");
    return uint16_t(d[p] | (d[p + 1] << 8));
}

inline void rgb565(uint16_t c, int out[3]) {
    out[0] = ((c >> 11) & 31) * 255 / 31;
    out[1] = ((c >> 5) & 63) * 255 / 63;
    out[2] = (c & 31) * 255 / 31;
}

inline image dxt(const uint8_t* d, size_t n, int w, int h, bool dxt5) {
    image img{w, h, bytes(size_t(w) * h * 4)};
    size_t need = size_t((w + 3) / 4) * ((h + 3) / 4) * (dxt5 ? 16 : 8);
    if (n < need) throw std::runtime_error("DXT data truncated");
    size_t pos = 0;
    for (int by = 0; by < h; by += 4) {
        for (int bx = 0; bx < w; bx += 4) {
            int alpha[16];
            bool has_alpha = false;
            if (dxt5) {
                int a0 = d[pos], a1 = d[pos + 1];
                uint64_t bits = 0;
                for (int i = 0; i < 6; ++i) bits |= uint64_t(d[pos + 2 + i]) << (8 * i);
                pos += 8;
                int pal[8] = {a0, a1};
                if (a0 > a1) {
                    for (int i = 1; i < 7; ++i) pal[i + 1] = ((7 - i) * a0 + i * a1) / 7;
                } else {
                    for (int i = 1; i < 5; ++i) pal[i + 1] = ((5 - i) * a0 + i * a1) / 5;
                    pal[6] = 0;
                    pal[7] = 255;
                }
                for (int i = 0; i < 16; ++i) alpha[i] = pal[(bits >> (3 * i)) & 7];
                has_alpha = true;
            }
            uint16_t c0 = uint16_t(d[pos] | (d[pos + 1] << 8)), c1 = uint16_t(d[pos + 2] | (d[pos + 3] << 8));
            uint32_t idx = uint32_t(d[pos + 4]) | (uint32_t(d[pos + 5]) << 8) | (uint32_t(d[pos + 6]) << 16) | (uint32_t(d[pos + 7]) << 24);
            pos += 8;
            int p0[3], p1[3], cols[4][4];
            rgb565(c0, p0);
            rgb565(c1, p1);
            for (int k = 0; k < 3; ++k) {
                cols[0][k] = p0[k];
                cols[1][k] = p1[k];
                if (c0 > c1 || dxt5) {
                    cols[2][k] = (2 * p0[k] + p1[k]) / 3;
                    cols[3][k] = (p0[k] + 2 * p1[k]) / 3;
                } else {
                    cols[2][k] = (p0[k] + p1[k]) / 2;
                    cols[3][k] = 0;
                }
            }
            cols[0][3] = cols[1][3] = cols[2][3] = 255;
            cols[3][3] = (c0 > c1 || dxt5) ? 255 : 0;
            for (int i = 0; i < 16; ++i) {
                int x = bx + (i & 3), y = by + (i >> 2);
                if (x >= w || y >= h) continue;
                const int* c = cols[(idx >> (2 * i)) & 3];
                uint8_t* o = &img.rgba[(size_t(y) * w + x) * 4];
                o[0] = uint8_t(c[0]);
                o[1] = uint8_t(c[1]);
                o[2] = uint8_t(c[2]);
                o[3] = uint8_t(has_alpha ? alpha[i] : c[3]);
            }
        }
    }
    return img;
}

}  // namespace detail

// Decodes the smallest mipmap at least `want` pixels on its longer side (or the largest there is).
inline image paa(const bytes& d, int want) {
    using detail::u16;
    uint16_t kind = u16(d, 0);
    size_t pos = 2;
    while (pos + 12 <= d.size() && std::memcmp(&d[pos], "GGAT", 4) == 0) {
        uint32_t len = uint32_t(d[pos + 8]) | (uint32_t(d[pos + 9]) << 8) | (uint32_t(d[pos + 10]) << 16) | (uint32_t(d[pos + 11]) << 24);
        pos += 12 + size_t(len);
    }
    pos += 2 + 3 * size_t(u16(d, pos));  // palette
    struct mip { uint16_t w, h; size_t at, size; };
    std::vector<mip> mips;
    while (pos + 7 <= d.size()) {
        uint16_t w = u16(d, pos), h = u16(d, pos + 2);
        if (w == 0 || h == 0) break;
        size_t size = size_t(d[pos + 4]) | (size_t(d[pos + 5]) << 8) | (size_t(d[pos + 6]) << 16);
        if (pos + 7 + size > d.size()) break;
        mips.push_back({w, h, pos + 7, size});
        pos += 7 + size;
    }
    if (mips.empty()) throw std::runtime_error("no mipmaps");
    mip pick = mips[0];
    for (const mip& m : mips)
        if (std::max(m.w & 0x7FFF, int(m.h)) >= want) pick = m;
    bool lzo = pick.w & 0x8000;
    int w = pick.w & 0x7FFF, h = pick.h;
    const uint8_t* data = &d[pick.at];
    if (kind == 0xFF01 || kind == 0xFF05) {
        size_t raw = size_t((w + 3) / 4) * ((h + 3) / 4) * (kind == 0xFF01 ? 8 : 16);
        if (lzo) {
            bytes un = lzo1x(data, pick.size, raw);
            return detail::dxt(un.data(), un.size(), w, h, kind == 0xFF05);
        }
        return detail::dxt(data, pick.size, w, h, kind == 0xFF05);
    }
    if (kind != 0x8888 && kind != 0x8080 && kind != 0x4444 && kind != 0x1555) throw std::runtime_error("unsupported PAA type");
    size_t bpp = kind == 0x8888 ? 4 : 2, raw = size_t(w) * h * bpp;
    bytes un = pick.size < raw ? lzss(data, pick.size, raw) : bytes(data, data + raw);
    image img{w, h, bytes(size_t(w) * h * 4)};
    for (size_t i = 0; i < size_t(w) * h; ++i) {
        uint8_t* o = &img.rgba[i * 4];
        if (kind == 0x8888) {  // stored B, G, R, A
            o[0] = un[i * 4 + 2]; o[1] = un[i * 4 + 1]; o[2] = un[i * 4]; o[3] = un[i * 4 + 3];
        } else if (kind == 0x8080) {  // grey and alpha
            o[0] = o[1] = o[2] = un[i * 2]; o[3] = un[i * 2 + 1];
        } else {
            unsigned v = un[i * 2] | (un[i * 2 + 1] << 8);
            if (kind == 0x4444) {
                o[3] = uint8_t(((v >> 12) & 15) * 17); o[0] = uint8_t(((v >> 8) & 15) * 17);
                o[1] = uint8_t(((v >> 4) & 15) * 17); o[2] = uint8_t((v & 15) * 17);
            } else {
                o[3] = (v & 0x8000) ? 255 : 0; o[0] = uint8_t(((v >> 10) & 31) * 255 / 31);
                o[1] = uint8_t(((v >> 5) & 31) * 255 / 31); o[2] = uint8_t((v & 31) * 255 / 31);
            }
        }
    }
    return img;
}

// ---------- PNG ----------

namespace detail {

inline uint32_t crc32(const uint8_t* p, size_t n, uint32_t crc = 0) {
    static uint32_t table[256] = {};
    if (!table[1]) {
        for (uint32_t i = 0; i < 256; ++i) {
            uint32_t c = i;
            for (int k = 0; k < 8; ++k) c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
            table[i] = c;
        }
    }
    crc = ~crc;
    for (size_t i = 0; i < n; ++i) crc = table[(crc ^ p[i]) & 0xFF] ^ (crc >> 8);
    return ~crc;
}

inline void be32(std::string& s, uint32_t v) {
    for (int k = 3; k >= 0; --k) s += char((v >> (8 * k)) & 0xFF);
}

}  // namespace detail

// An RGBA PNG. The image data is stored uncompressed (deflate "stored" blocks), so no zlib is needed;
// map icons are small.
inline std::string png(const image& img) {
    std::string raw;
    for (int y = 0; y < img.h; ++y) {
        raw += '\0';
        raw.append(reinterpret_cast<const char*>(&img.rgba[size_t(y) * img.w * 4]), size_t(img.w) * 4);
    }
    std::string z = "\x78\x01";
    uint32_t a = 1, b = 0;
    for (unsigned char c : raw) { a = (a + c) % 65521; b = (b + a) % 65521; }
    for (size_t i = 0; i < raw.size() || i == 0; i += 65535) {
        size_t len = std::min<size_t>(65535, raw.size() - i);
        z += char(i + len >= raw.size() ? 1 : 0);
        z += char(len & 0xFF); z += char(len >> 8);
        z += char(~len & 0xFF); z += char((~len >> 8) & 0xFF);
        z.append(raw, i, len);
    }
    detail::be32(z, (b << 16) | a);
    std::string out = "\x89PNG\r\n\x1a\n";
    auto chunk = [&](const char* tag, const std::string& body) {
        detail::be32(out, uint32_t(body.size()));
        std::string t = std::string(tag, 4) + body;
        out += t;
        detail::be32(out, detail::crc32(reinterpret_cast<const uint8_t*>(t.data()), t.size()));
    };
    std::string ihdr;
    detail::be32(ihdr, uint32_t(img.w));
    detail::be32(ihdr, uint32_t(img.h));
    ihdr += std::string("\x08\x06\x00\x00\x00", 5);
    chunk("IHDR", ihdr);
    chunk("IDAT", z);
    chunk("IEND", "");
    return out;
}

inline std::string base64(const std::string& s) {
    static const char* t = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string out;
    size_t i = 0;
    for (; i + 2 < s.size(); i += 3) {
        uint32_t v = (uint8_t(s[i]) << 16) | (uint8_t(s[i + 1]) << 8) | uint8_t(s[i + 2]);
        out += t[v >> 18]; out += t[(v >> 12) & 63]; out += t[(v >> 6) & 63]; out += t[v & 63];
    }
    if (i < s.size()) {
        uint32_t v = uint8_t(s[i]) << 16;
        if (i + 1 < s.size()) v |= uint8_t(s[i + 1]) << 8;
        out += t[v >> 18]; out += t[(v >> 12) & 63];
        out += i + 1 < s.size() ? t[(v >> 6) & 63] : '=';
        out += '=';
    }
    return out;
}

// ---------- PBO ----------

struct pbo_entry {
    std::filesystem::path pbo;
    uint64_t offset = 0;
    uint32_t size = 0, original = 0;
    bool packed = false;
};

// Adds the .paa files in a PBO, by their path inside the game, to `index` (first one found wins).
inline void pbo_index(const std::filesystem::path& file, std::map<std::string, pbo_entry>& index) {
    std::ifstream f(file, std::ios::binary);
    if (!f) return;
    auto zstr = [&]() {
        std::string s;
        char c;
        while (f.get(c) && c) s += c;
        if (!f) throw std::runtime_error("truncated PBO header");
        return s;
    };
    auto u32 = [&]() {
        uint8_t b[4];
        if (!f.read(reinterpret_cast<char*>(b), 4)) throw std::runtime_error("truncated PBO header");
        return uint32_t(b[0]) | (uint32_t(b[1]) << 8) | (uint32_t(b[2]) << 16) | (uint32_t(b[3]) << 24);
    };
    struct raw { std::string name; uint32_t size, original; bool packed; };
    std::vector<raw> entries;
    std::string prefix;
    for (bool first = true;; first = false) {
        std::string name = zstr();
        uint32_t method = u32(), original = u32();
        u32();
        u32();
        uint32_t size = u32();
        if (first && name.empty() && method == 0x56657273) {  // "Vers": header extensions
            for (;;) {
                std::string key = zstr();
                if (key.empty()) break;
                std::string value = zstr();
                std::string lower;
                for (char c : key) lower += (c >= 'A' && c <= 'Z') ? char(c - 'A' + 'a') : c;
                if (lower == "prefix") prefix = value;
            }
            continue;
        }
        if (name.empty()) break;
        entries.push_back({name, size, original, method == 0x43707273});
    }
    uint64_t offset = uint64_t(f.tellg());
    std::string pre;
    for (char c : prefix) pre += c == '/' ? '\\' : (c >= 'A' && c <= 'Z') ? char(c - 'A' + 'a') : c;
    while (!pre.empty() && pre.back() == '\\') pre.pop_back();
    while (!pre.empty() && pre.front() == '\\') pre.erase(0, 1);
    for (const raw& e : entries) {
        std::string path = norm((pre.empty() ? "" : pre + "\\") + e.name);
        if (path.size() > 4 && path.compare(path.size() - 4, 4, ".paa") == 0 && !index.count(path))
            index[path] = {file, offset, e.size, e.original, e.packed};
        offset += e.size;
    }
}

// ---------- JSON helpers ----------

inline std::string json_string(std::string_view s) {
    std::string out = "\"";
    for (char c : s) {
        if (c == '"' || c == '\\') { out += '\\'; out += c; }
        else if (uint8_t(c) < 0x20) { char buf[8]; std::snprintf(buf, sizeof buf, "\\u%04x", c); out += buf; }
        else out += c;
    }
    return out + "\"";
}

// The strings in a flat JSON array of strings, as toJSON writes it.
inline std::vector<std::string> json_strings(std::string_view s) {
    std::vector<std::string> out;
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] != '"') continue;
        std::string v;
        for (++i; i < s.size() && s[i] != '"'; ++i) {
            if (s[i] == '\\' && i + 1 < s.size()) {
                char e = s[++i];
                if (e == 'n') v += '\n';
                else if (e == 't') v += '\t';
                else if (e == 'u' && i + 4 < s.size()) { v += char(std::stoi(std::string(s.substr(i + 1, 4)), nullptr, 16) & 0x7F); i += 4; }
                else v += e;
            } else {
                v += s[i];
            }
        }
        out.push_back(std::move(v));
    }
    return out;
}

// The members of a JSON object without its braces, so several can be joined.
inline std::string_view json_members(std::string_view obj) {
    size_t a = obj.find('{'), b = obj.rfind('}');
    if (a == std::string_view::npos || b == std::string_view::npos || b <= a) return {};
    obj = obj.substr(a + 1, b - a - 1);
    while (!obj.empty() && (obj.front() == ' ' || obj.front() == '\n')) obj.remove_prefix(1);
    return obj;
}

// ---------- the export ----------

struct job {
    std::filesystem::path dir;           // where the recordings go
    std::string key;                     // game version and mod list
    std::string header;                  // extra top-level members for aar-cfg.json, as a JSON object
    std::map<std::string, std::string> tables;  // "vehicles" -> joined object members
    std::vector<std::string> textures;   // texture paths to export
    std::vector<std::filesystem::path> search;  // folders searched for PBOs
    int size = 32;                       // smallest mipmap side kept
};

inline bool write_file(const std::filesystem::path& path, const std::string& text) {
    std::error_code ec;
    auto tmp = path;
    tmp += ".tmp";
    {
        std::ofstream f(tmp, std::ios::binary | std::ios::trunc);
        if (!f || !f.write(text.data(), std::streamsize(text.size()))) return false;
    }
    std::filesystem::rename(tmp, path, ec);
    return !ec;
}

// Returns a line for the log.
inline std::string run(const job& j) {
    namespace fs = std::filesystem;
    std::string cfg = "{\"format\":\"aar-cfg\",\"version\":1,\"key\":" + json_string(j.key);
    std::string_view head = json_members(j.header);
    if (!head.empty()) cfg += "," + std::string(head);
    for (const auto& [name, members] : j.tables) cfg += "," + json_string(name) + ":{" + members + "}";
    cfg += "}";
    if (!write_file(j.dir / "aar-cfg.json", cfg)) return "could not write aar-cfg.json";

    std::map<std::string, pbo_entry> index;
    size_t pbos = 0;
    for (const fs::path& root : j.search) {
        std::error_code ec;
        if (!fs::is_directory(root, ec)) continue;
        for (fs::recursive_directory_iterator it(root, fs::directory_options::follow_directory_symlink | fs::directory_options::skip_permission_denied, ec), end;
             it != end; it.increment(ec)) {
            if (ec) break;
            std::string ext = it->path().extension().string();
            if (ext.size() != 4 || norm(ext) != ".pbo") continue;
            ++pbos;
            try { pbo_index(it->path(), index); } catch (const std::exception&) {}
        }
    }

    std::map<std::string, std::string> icons;
    size_t failed = 0, missing = 0;
    for (const std::string& t : j.textures) {
        std::string key = norm(t);
        if (key.empty() || icons.count(key)) continue;
        auto e = index.find(key);
        if (e == index.end()) { ++missing; continue; }
        try {
            std::ifstream f(e->second.pbo, std::ios::binary);
            f.seekg(std::streamoff(e->second.offset));
            bytes data(e->second.size);
            if (!f.read(reinterpret_cast<char*>(data.data()), std::streamsize(data.size()))) throw std::runtime_error("read failed");
            if (e->second.packed) data = lzss(data.data(), data.size(), e->second.original);
            icons[key] = "data:image/png;base64," + base64(png(paa(data, j.size)));
        } catch (const std::exception&) {
            ++failed;
        }
    }
    std::string pack = "{\"format\":\"aar-icons\",\"version\":1,\"icons\":{";
    bool first = true;
    for (const auto& [k, v] : icons) {
        pack += (first ? "" : ",") + json_string(k) + ":\"" + v + "\"";
        first = false;
    }
    pack += "}}";
    if (!write_file(j.dir / "aar-icons.json", pack)) return "could not write aar-icons.json";
    // Last, so an export cut short is redone next mission.
    write_file(j.dir / "aar-gamedata.key", j.key);
    return std::to_string(pbos) + " PBOs searched, " + std::to_string(icons.size()) + " icons written, " +
           std::to_string(failed) + " failed, " + std::to_string(missing) + " not found";
}

inline std::string stored_key(const std::filesystem::path& dir) {
    std::ifstream f(dir / "aar-gamedata.key", std::ios::binary);
    return std::string(std::istreambuf_iterator<char>(f), std::istreambuf_iterator<char>());
}

}  // namespace aar::gamedata
