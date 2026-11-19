/* Copyright (c) 2026 Bruce A Henderson and contributors
 * SPDX-License-Identifier: Zlib */
#include "../../../archive.mod/zlib.mod/zlib/zlib.h"
#include <string.h>

int _ws_deflate(const unsigned char *source, int source_length,
                unsigned char *output, int output_capacity) {
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    if (deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -9, 1,
                     Z_DEFAULT_STRATEGY) != Z_OK) return -1;
    stream.next_in = (Bytef *)source;
    stream.avail_in = (uInt)source_length;
    stream.next_out = output;
    stream.avail_out = (uInt)output_capacity;
    int status = deflate(&stream, Z_SYNC_FLUSH);
    int count = -1;
    if (status == Z_OK && stream.avail_in == 0 && stream.avail_out > 0 &&
        stream.total_out >= 4 &&
        memcmp(output + stream.total_out - 4, "\x00\x00\xff\xff", 4) == 0)
        count = (int)stream.total_out - 4;
    deflateEnd(&stream);
    return count;
}

int _ws_inflate(const unsigned char *source, int source_length,
                unsigned char *output, int output_capacity) {
    static const unsigned char tail[] = {0, 0, 255, 255};
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    if (inflateInit2(&stream, -9) != Z_OK) return -3;
    stream.next_in = (Bytef *)source;
    stream.avail_in = (uInt)source_length;
    stream.next_out = output;
    stream.avail_out = (uInt)output_capacity;
    int status = inflate(&stream, Z_SYNC_FLUSH);
    if ((status == Z_OK || status == Z_BUF_ERROR) && stream.avail_in == 0) {
        stream.next_in = (Bytef *)tail;
        stream.avail_in = 4;
        status = inflate(&stream, Z_SYNC_FLUSH);
    }
    int count = -1;
    if (stream.avail_out == 0) count = -2;
    if (status == Z_OK && stream.avail_in == 0 && stream.avail_out > 0)
        count = (int)stream.total_out;
    inflateEnd(&stream);
    return count;
}
