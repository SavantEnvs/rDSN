// First input byte picks the target type, the rest is the JSON text handed to dsn::json's decoder.
#include <dsn/cpp/json_helper.h>
#include <dsn/cpp/blob.h>
#include <dsn/cpp/serialization_helper/dsn.layer2_types.h>
#include <cstdint>
#include <cstring>
#include <map>
#include <memory>
#include <string>
#include <vector>

template <class T> static void roundtrip(const dsn::blob &bb)
{
    T value;
    if (dsn::json::json_forwarder<T>::decode(bb, value))
    {
        std::stringstream out;
        dsn::json::json_forwarder<T>::encode(out, value);
    }
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    if (size < 1)
        return 0;
    const uint8_t kind = data[0] % 6;
    ++data;
    --size;

    std::shared_ptr<char> buf(new char[size + 1], std::default_delete<char[]>());
    if (size)
        memcpy(buf.get(), data, size);
    buf.get()[size] = '\0';
    dsn::blob bb(buf, (unsigned int)size);

    switch (kind)
    {
    case 0: roundtrip<dsn::partition_configuration>(bb); break;
    case 1: roundtrip<dsn::app_info>(bb); break;
    case 2: roundtrip<std::map<std::string, std::string>>(bb); break;
    case 3: roundtrip<std::vector<std::vector<int>>>(bb); break;
    case 4: roundtrip<std::vector<dsn::rpc_address>>(bb); break;
    default: roundtrip<std::map<std::string, std::vector<dsn::gpid>>>(bb); break;
    }
    return 0;
}
