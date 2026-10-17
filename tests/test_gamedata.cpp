// Checks the game data export: LZO/LZSS, PAA decoding, PNG, PBO reading and the files written.
// With paths as arguments, decodes those .paa files and writes <name>.png next to the test binary.
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <string>

#include "gamedata.hpp"

namespace fs = std::filesystem;
using namespace aar::gamedata;

static int failures = 0;
#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            ++failures;                                                 \
            std::printf("FAIL line %d: %s\n", __LINE__, #cond);         \
        }                                                               \
    } while (0)

static bytes hex(const char* h) {
    bytes out;
    for (; h[0] && h[1]; h += 2) out.push_back(uint8_t(std::stoi(std::string(h, 2), nullptr, 16)));
    return out;
}

static void put16(bytes& b, unsigned v) { b.push_back(uint8_t(v)); b.push_back(uint8_t(v >> 8)); }
static void put32(std::string& s, uint32_t v) { for (int i = 0; i < 4; ++i) s += char((v >> (8 * i)) & 0xFF); }

static bytes dxt1_block(uint16_t c0, uint16_t c1, const int idx[16]) {
    bytes b;
    put16(b, c0);
    put16(b, c1);
    uint32_t bits = 0;
    for (int i = 0; i < 16; ++i) bits |= uint32_t(idx[i]) << (2 * i);
    for (int i = 0; i < 4; ++i) b.push_back(uint8_t(bits >> (8 * i)));
    return b;
}

static bytes paa_file(uint16_t kind, uint16_t w, uint16_t h, const bytes& data) {
    bytes b;
    put16(b, kind);
    put16(b, 0);  // palette
    put16(b, w);
    put16(b, h);
    b.push_back(uint8_t(data.size()));
    b.push_back(uint8_t(data.size() >> 8));
    b.push_back(uint8_t(data.size() >> 16));
    b.insert(b.end(), data.begin(), data.end());
    for (int i = 0; i < 6; ++i) b.push_back(0);
    return b;
}

int main(int argc, char** argv) {
    if (argc > 1) {
        for (int i = 1; i < argc; ++i) {
            std::ifstream f(argv[i], std::ios::binary);
            bytes d((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
            try {
                image img = paa(d, 64);
                std::ofstream(fs::path(argv[i]).stem().string() + ".png", std::ios::binary) << png(img);
            } catch (const std::exception& e) {
                ++failures;
                std::printf("FAIL %s: %s\n", argv[i], e.what());
            }
        }
        return failures ? 1 : 0;
    }

    CHECK(norm("\\A3\\ui_f\\data\\Map\\VehicleIcons\\iconMan_ca") == "a3\\ui_f\\data\\map\\vehicleicons\\iconman_ca.paa");
    CHECK(norm("a3/ui_f/x.paa") == "a3\\ui_f\\x.paa");

    // python-lzo's lzo.compress(data, 1, False), as in tests/test_export_icons.py.
    std::string want;
    for (int i = 0; i < 40; ++i) want += "\x11\x22\x33\x44";
    for (int i = 0; i < 64; ++i) want += char(i);
    for (int i = 0; i < 30; ++i) want += "abc";
    bytes packed = hex(
        "05112233441122334420771c000031000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        "202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f61626320230800000163616263616263"
        "616263616263616263616263110000");
    bytes un = lzo1x(packed.data(), packed.size(), want.size());
    CHECK(std::string(un.begin(), un.end()) == want);
    bool threw = false;
    try { lzo1x(packed.data(), packed.size() - 10, want.size()); } catch (const std::exception&) { threw = true; }
    CHECK(threw);

    bytes lz = {0x0F, 'a', 'b', 'c', 'd', 4, 3};
    bytes ls = lzss(lz.data(), lz.size(), 10);
    CHECK(std::string(ls.begin(), ls.end()) == "abcdabcdab");

    int idx[16] = {0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1};
    image img = paa(paa_file(0xFF01, 4, 4, dxt1_block(0xF800, 0x001F, idx)), 32);
    CHECK(img.w == 4 && img.h == 4);
    CHECK(img.rgba[0] == 255 && img.rgba[1] == 0 && img.rgba[2] == 0 && img.rgba[3] == 255);
    CHECK(img.rgba[60] == 0 && img.rgba[62] == 255);

    std::string p = png(img);
    CHECK(p.compare(0, 8, "\x89PNG\r\n\x1a\n") == 0);
    CHECK(base64("abcd") == "YWJjZA==");

    CHECK((json_strings(R"(["a\\b","c\"d",""])") == std::vector<std::string>{"a\\b", "c\"d", ""}));
    CHECK(json_members(R"({"x":[1,2]})") == R"("x":[1,2])");

    // A PBO with a prefix, read through the whole export.
    fs::path dir = fs::temp_directory_path() / "aar_gamedata_test";
    fs::remove_all(dir);
    fs::create_directories(dir / "game" / "Addons");
    bytes icon = paa_file(0xFF01, 4, 4, dxt1_block(0xFFFF, 0xFFFF, idx));
    std::string pbo;
    pbo += '\0';
    put32(pbo, 0x56657273); put32(pbo, 0); put32(pbo, 0); put32(pbo, 0); put32(pbo, 0);
    pbo += std::string("prefix\0a3\\ui_f\0\0", 16);
    for (const char* name : {"data\\map\\vehicleicons\\iconMan_ca.paa", "config.bin"}) {
        pbo += name;
        pbo += '\0';
        uint32_t size = std::string(name) == "config.bin" ? 3 : uint32_t(icon.size());
        put32(pbo, 0); put32(pbo, size); put32(pbo, 0); put32(pbo, 0); put32(pbo, size);
    }
    pbo += std::string(21, '\0');
    pbo.append(icon.begin(), icon.end());
    pbo += "xyz";
    std::ofstream(dir / "game" / "Addons" / "ui_f.pbo", std::ios::binary) << pbo;

    job j;
    j.dir = dir;
    j.key = "2.22|a3";
    j.header = R"({"game":222})";
    j.tables["weapons"] = R"("arifle_MX_F":["MX 6.5 mm",""])";
    j.textures = {"\\A3\\ui_f\\data\\map\\VehicleIcons\\iconMan_ca.paa", "\\A3\\missing.paa"};
    j.search = {dir / "game" / "Addons"};
    std::string result = run(j);
    CHECK(result == "1 PBOs searched, 1 icons written, 0 failed, 1 not found");
    std::ifstream cf(dir / "aar-cfg.json");
    std::string cfg((std::istreambuf_iterator<char>(cf)), std::istreambuf_iterator<char>());
    CHECK(cfg == R"({"format":"aar-cfg","version":1,"key":"2.22|a3","game":222,"weapons":{"arifle_MX_F":["MX 6.5 mm",""]}})");
    std::ifstream pf(dir / "aar-icons.json");
    std::string pack((std::istreambuf_iterator<char>(pf)), std::istreambuf_iterator<char>());
    CHECK(pack.find(R"("a3\\ui_f\\data\\map\\vehicleicons\\iconman_ca.paa":"data:image/png;base64,iVBORw0KGgo)") != std::string::npos);
    CHECK(stored_key(dir) == "2.22|a3");
    fs::remove_all(dir);

    if (failures) std::printf("%d failure(s)\n", failures);
    else std::printf("all game data tests passed\n");
    return failures ? 1 : 0;
}
