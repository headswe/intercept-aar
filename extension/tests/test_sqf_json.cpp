// Checks the SQF record -> JSON line conversion.
#include <cstdio>
#include <string>

#include "sqf_json.hpp"

static int failures = 0;

static void expect(const std::string& in, const std::string& want) {
    std::string got;
    aar::sqf_records_to_json(in, got);
    if (got != want) {
        ++failures;
        std::printf("FAIL\n  in:   %s\n  got:  %s\n  want: %s\n", in.c_str(), got.c_str(), want.c_str());
    }
}

int main() {
    // What callExtension hands the extension for a string argument.
    if (aar::unquote_sqf(R"("{""type"":""x""}")") != R"({"type":"x"})") {
        ++failures;
        std::printf("FAIL unquote_sqf\n");
    }
    expect(R"({"type":"snap","t":12.50,"key":true,"e":[[1,14520.40,16710.12,17.30,92,1,0.00,0]]})",
           "{\"type\":\"snap\",\"t\":12.5,\"key\":true,\"e\":[[1,14520.4,16710.12,17.3,92,1,0,0]]}\n");
    // SQF doubles quotes; backslashes and newlines are raw.
    expect("{\"name\":\"say \"\"hi\"\"\",\"path\":\"C:\\x\",\"text\":\"a\nb\",\"empty\":\"\"}",
           "{\"name\":\"say \\\"hi\\\"\",\"path\":\"C:\\\\x\",\"text\":\"a\\nb\",\"empty\":\"\"}\n");
    // Two records in one call; blank lines ignored.
    expect("{\"a\":1}\n\n{\"b\":-0.00}\n", "{\"a\":1}\n{\"b\":0}\n");
    // Engine oddities outside strings become 0.
    expect("{\"a\":nan,\"b\":-1.#IND,\"c\":1e+006,\"d\":-3.10}", "{\"a\":0,\"b\":0,\"c\":1e+006,\"d\":-3.1}\n");
    expect("{\"s\":\"ends with quote\"\"\"}", "{\"s\":\"ends with quote\\\"\"}\n");
    std::printf(failures ? "%d failure(s)\n" : "all passed\n", failures);
    return failures ? 1 : 0;
}
