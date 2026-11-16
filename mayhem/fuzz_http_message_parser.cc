#include "parser_harness.h"
#include "http_message_parser.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    return fuzz_parser<dsn::http_message_parser>(data, size);
}
