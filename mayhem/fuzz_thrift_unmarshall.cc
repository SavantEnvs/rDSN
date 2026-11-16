// First byte: low bit picks thrift binary vs thrift JSON protocol, the rest of the bits pick the
// message type. The remaining bytes go to dsn::unmarshall, as an RPC payload would.
#include <dsn/cpp/serialization.h>
#include <dsn/cpp/serialization_helper/dsn.layer2_types.h>
#include <cstdint>
#include <cstring>
#include <memory>

template <class T> static void decode(const dsn::blob &bb, dsn_msg_serialize_format fmt)
{
    T value;
    try
    {
        dsn::binary_reader reader(bb);
        dsn::unmarshall(reader, value, fmt);
    }
    catch (...)
    {
    }
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    if (size < 1)
        return 0;
    const dsn_msg_serialize_format fmt = (data[0] & 1) ? DSF_THRIFT_JSON : DSF_THRIFT_BINARY;
    const unsigned kind = (data[0] >> 1) % 4;
    ++data;
    --size;

    std::shared_ptr<char> buf(new char[size + 1], std::default_delete<char[]>());
    if (size)
        memcpy(buf.get(), data, size);
    dsn::blob bb(buf, (unsigned int)size);

    switch (kind)
    {
    case 0: decode<dsn::partition_configuration>(bb, fmt); break;
    case 1: decode<dsn::configuration_query_by_index_request>(bb, fmt); break;
    case 2: decode<dsn::configuration_query_by_index_response>(bb, fmt); break;
    default: decode<dsn::app_info>(bb, fmt); break;
    }
    return 0;
}
