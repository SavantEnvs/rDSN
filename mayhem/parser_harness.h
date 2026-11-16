// Shared body of the message-parser harnesses: feeds the input to a parser the way
// asio_rpc_session does (read_buffer_ptr -> memcpy -> mark_read -> get_message_on_receive loop).
#pragma once
#include <dsn/tool-api/message_parser.h>
#include <dsn/tool-api/rpc_message.h>
#include <cstdint>
#include <cstring>

template <class Parser>
static int fuzz_parser(const uint8_t *data, size_t size)
{
    if (size < 2)
        return 0;
    // First byte selects the chunk size so partial headers/bodies are exercised.
    const size_t chunk = 1 + (data[0] % 64) * 7;
    ++data;
    --size;

    Parser parser;
    dsn::message_reader reader(4096);
    int read_next = 0;
    size_t off = 0;
    while (off < size)
    {
        size_t n = size - off < chunk ? size - off : chunk;
        char *buf = reader.read_buffer_ptr((unsigned int)n);
        if (buf == nullptr)
            break;
        memcpy(buf, data + off, n);
        reader.mark_read((unsigned int)n);
        off += n;

        dsn::message_ex *msg = parser.get_message_on_receive(&reader, read_next);
        while (msg != nullptr)
        {
            msg->add_ref();
            msg->release_ref();
            msg = parser.get_message_on_receive(&reader, read_next);
        }
        if (read_next == -1)
            break;
    }
    return 0;
}
