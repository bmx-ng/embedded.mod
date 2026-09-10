#include <stddef.h>
#include <stdint.h>

#include "blitzmax/embedded_runtime.h"

static const BMXEmbeddedString *bmx_embedded_string_from_unsigned(uint64_t value, int negative) {
    char buffer[21];
    char *end = buffer + sizeof(buffer);
    char *cursor = end;
    do {
        *--cursor = (char)('0' + value % 10u);
        value /= 10u;
    } while (value);
    if (negative) *--cursor = '-';
    return bmx_embedded_string_from_ascii(cursor, (int32_t)(end - cursor));
}

const BMXEmbeddedString *bmx_embedded_string_from_int32(int32_t value) {
    uint32_t magnitude = value < 0 ? 0u - (uint32_t)value : (uint32_t)value;
    return bmx_embedded_string_from_unsigned(magnitude, value < 0);
}

const BMXEmbeddedString *bmx_embedded_string_from_uint32(uint32_t value) {
    return bmx_embedded_string_from_unsigned(value, 0);
}

const BMXEmbeddedString *bmx_embedded_string_from_int64(int64_t value) {
    uint64_t magnitude = value < 0 ? 0u - (uint64_t)value : (uint64_t)value;
    return bmx_embedded_string_from_unsigned(magnitude, value < 0);
}

const BMXEmbeddedString *bmx_embedded_string_from_uint64(uint64_t value) {
    return bmx_embedded_string_from_unsigned(value, 0);
}

const BMXEmbeddedString *bmx_embedded_string_from_size(size_t value) {
    return bmx_embedded_string_from_unsigned((uint64_t)value, 0);
}

const BMXEmbeddedString *bmx_embedded_string_from_long(long value) {
    uint64_t magnitude = value < 0 ? 0u - (uint64_t)value : (uint64_t)value;
    return bmx_embedded_string_from_unsigned(magnitude, value < 0);
}

const BMXEmbeddedString *bmx_embedded_string_from_ulong(unsigned long value) {
    return bmx_embedded_string_from_unsigned((uint64_t)value, 0);
}

static int bmx_embedded_ascii_space(uint16_t character) {
    return character == ' ' || (character >= '\t' && character <= '\r');
}

static uint64_t bmx_embedded_string_parse_range(const uint16_t *characters, int32_t length, int32_t *end_index) {
    int32_t index = 0;
    int negative = 0;
    uint64_t value = 0;
    while (characters && index < length && bmx_embedded_ascii_space(characters[index])) ++index;
    if (!characters || index == length) {
        if (end_index) *end_index = index;
        return 0;
    }
    if (characters[index] == '+') ++index;
    else if (characters[index] == '-') {
        negative = 1;
        ++index;
    }
    if (index == length) {
        if (end_index) *end_index = index;
        return 0;
    }
    uint32_t base = 10;
    if (characters[index] == '%') {
        base = 2;
        ++index;
    } else if (characters[index] == '$') {
        base = 16;
        ++index;
    }
    for (; index < length; ++index) {
        uint16_t character = characters[index];
        uint32_t digit;
        if (character >= '0' && character <= '9') digit = character - '0';
        else if (character >= 'A' && character <= 'F') digit = character - 'A' + 10u;
        else if (character >= 'a' && character <= 'f') digit = character - 'a' + 10u;
        else break;
        if (digit >= base) break;
        value = value * base + digit;
    }
    if (end_index) *end_index = index;
    return negative ? 0u - value : value;
}

static uint64_t bmx_embedded_string_parse_unsigned(const BMXEmbeddedString *text) {
    return text ? bmx_embedded_string_parse_range(text->buf, text->length, NULL) : 0;
}

int32_t bmx_embedded_string_to_int32(const BMXEmbeddedString *text) {
    return (int32_t)bmx_embedded_string_parse_unsigned(text);
}

uint32_t bmx_embedded_string_to_uint32(const BMXEmbeddedString *text) {
    return (uint32_t)bmx_embedded_string_parse_unsigned(text);
}

int64_t bmx_embedded_string_to_int64(const BMXEmbeddedString *text) {
    return (int64_t)bmx_embedded_string_parse_unsigned(text);
}

uint64_t bmx_embedded_string_to_uint64(const BMXEmbeddedString *text) {
    return bmx_embedded_string_parse_unsigned(text);
}

size_t bmx_embedded_string_to_size(const BMXEmbeddedString *text) {
    return (size_t)bmx_embedded_string_parse_unsigned(text);
}

long bmx_embedded_string_to_long(const BMXEmbeddedString *text) {
    return (long)bmx_embedded_string_parse_unsigned(text);
}

unsigned long bmx_embedded_string_to_ulong(const BMXEmbeddedString *text) {
    return (unsigned long)bmx_embedded_string_parse_unsigned(text);
}

static int bmx_embedded_separator_matches(const uint16_t *text, int32_t at,
    const uint16_t *separator, int32_t separator_length) {
    for (int32_t index = 0; index < separator_length; ++index) {
        if (text[at + index] != separator[index]) return 0;
    }
    return 1;
}

static int32_t bmx_embedded_numeric_part_count(const BMXEmbeddedString *text, const BMXEmbeddedString *separator) {
    if (!text || !text->length) return 0;
    if (!separator || !separator->length) return 1;
    int32_t count = 1;
    for (int32_t index = 0; index <= text->length - separator->length;) {
        if (bmx_embedded_separator_matches(text->buf, index, separator->buf, separator->length)) {
            ++count;
            index += separator->length;
        } else {
            ++index;
        }
    }
    return count;
}

static uint64_t bmx_embedded_parse_numeric_part(const uint16_t *characters, int32_t length) {
    if (length <= 0) return 0;
    int32_t end = 0;
    uint64_t value = bmx_embedded_string_parse_range(characters, length, &end);
    while (end < length && bmx_embedded_ascii_space(characters[end])) ++end;
    return end == length ? value : 0;
}

#define BMX_EMBEDDED_DEFINE_SPLIT_INTEGER(NAME, TYPE) \
BMXEmbeddedArray *NAME(const BMXEmbeddedString *text, const BMXEmbeddedString *separator) { \
    int32_t count = bmx_embedded_numeric_part_count(text, separator); \
    if (!count) return &bmx_embedded_empty_array; \
    BMXEmbeddedArray *result = bmx_embedded_array_new_1d(count, (uint32_t)sizeof(TYPE), \
        BMX_EMBEDDED_ARRAY_ELEMENT_VALUE, NULL, NULL); \
    if (result == &bmx_embedded_empty_array) return result; \
    TYPE *output = (TYPE *)bmx_embedded_array_data(result); \
    if (!separator || !separator->length) { \
        output[0] = (TYPE)bmx_embedded_parse_numeric_part(text->buf, text->length); \
        return result; \
    } \
    int32_t begin = 0; \
    int32_t part = 0; \
    for (int32_t index = 0; index <= text->length;) { \
        int match = index <= text->length - separator->length && \
            bmx_embedded_separator_matches(text->buf, index, separator->buf, separator->length); \
        if (match || index == text->length) { \
            output[part++] = (TYPE)bmx_embedded_parse_numeric_part(text->buf + begin, index - begin); \
            if (index == text->length) break; \
            index += separator->length; \
            begin = index; \
        } else { \
            ++index; \
        } \
    } \
    return result; \
}

BMX_EMBEDDED_DEFINE_SPLIT_INTEGER(bmx_embedded_string_split_ints, int32_t)
BMX_EMBEDDED_DEFINE_SPLIT_INTEGER(bmx_embedded_string_split_bytes, uint8_t)
BMX_EMBEDDED_DEFINE_SPLIT_INTEGER(bmx_embedded_string_split_shorts, uint16_t)
BMX_EMBEDDED_DEFINE_SPLIT_INTEGER(bmx_embedded_string_split_uints, uint32_t)
BMX_EMBEDDED_DEFINE_SPLIT_INTEGER(bmx_embedded_string_split_longs, int64_t)
BMX_EMBEDDED_DEFINE_SPLIT_INTEGER(bmx_embedded_string_split_ulongs, uint64_t)
BMX_EMBEDDED_DEFINE_SPLIT_INTEGER(bmx_embedded_string_split_sizes, size_t)
BMX_EMBEDDED_DEFINE_SPLIT_INTEGER(bmx_embedded_string_split_long_ints, long)
BMX_EMBEDDED_DEFINE_SPLIT_INTEGER(bmx_embedded_string_split_ulong_ints, unsigned long)

static int32_t bmx_embedded_decimal_length(uint64_t value) {
    int32_t length = 1;
    while (value >= 10u) {
        value /= 10u;
        ++length;
    }
    return length;
}

static uint16_t *bmx_embedded_write_unsigned(uint16_t *output, uint64_t value, int32_t length) {
    uint16_t *end = output + length;
    while (length--) {
        output[length] = (uint16_t)('0' + value % 10u);
        value /= 10u;
    }
    return end;
}

static const BMXEmbeddedString *bmx_embedded_join_integer(const BMXEmbeddedString *separator,
    BMXEmbeddedArray *values, uint32_t element_size, int is_signed) {
    if (!separator) separator = &bmx_embedded_empty_string;
    if (!values || values == &bmx_embedded_empty_array || !values->length) return &bmx_embedded_empty_string;
    if (values->element_kind != BMX_EMBEDDED_ARRAY_ELEMENT_VALUE || values->element_size != element_size) {
        return &bmx_embedded_empty_string;
    }
    const uint8_t *data = (const uint8_t *)bmx_embedded_array_data(values);
    int64_t total = (int64_t)(values->length - 1) * separator->length;
    for (int32_t index = 0; index < values->length; ++index) {
        uint64_t raw = 0;
        for (uint32_t byte = 0; byte < element_size; ++byte) raw |= (uint64_t)data[index * element_size + byte] << (byte * 8u);
        int negative = is_signed && (raw & (UINT64_C(1) << (element_size * 8u - 1u)));
        uint64_t magnitude = negative ? ((~raw + 1u) & (element_size == 8u ? UINT64_MAX : ((UINT64_C(1) << (element_size * 8u)) - 1u))) : raw;
        total += bmx_embedded_decimal_length(magnitude) + negative;
        if (total > INT32_MAX) return &bmx_embedded_empty_string;
    }
    BMXEmbeddedString *result = bmx_embedded_string_allocate((int32_t)total);
    if (result == &bmx_embedded_empty_string) return result;
    uint16_t *output = (uint16_t *)(uintptr_t)result->buf;
    for (int32_t index = 0; index < values->length; ++index) {
        if (index && separator->length) {
            for (int32_t unit = 0; unit < separator->length; ++unit) *output++ = separator->buf[unit];
        }
        uint64_t raw = 0;
        for (uint32_t byte = 0; byte < element_size; ++byte) raw |= (uint64_t)data[index * element_size + byte] << (byte * 8u);
        int negative = is_signed && (raw & (UINT64_C(1) << (element_size * 8u - 1u)));
        uint64_t magnitude = negative ? ((~raw + 1u) & (element_size == 8u ? UINT64_MAX : ((UINT64_C(1) << (element_size * 8u)) - 1u))) : raw;
        if (negative) *output++ = '-';
        output = bmx_embedded_write_unsigned(output, magnitude, bmx_embedded_decimal_length(magnitude));
    }
    return result;
}

#define BMX_EMBEDDED_DEFINE_JOIN_INTEGER(NAME, TYPE, SIGNED) \
const BMXEmbeddedString *NAME(const BMXEmbeddedString *separator, BMXEmbeddedArray *values) { \
    return bmx_embedded_join_integer(separator, values, (uint32_t)sizeof(TYPE), SIGNED); \
}

BMX_EMBEDDED_DEFINE_JOIN_INTEGER(bmx_embedded_string_join_ints, int32_t, 1)
BMX_EMBEDDED_DEFINE_JOIN_INTEGER(bmx_embedded_string_join_bytes, uint8_t, 0)
BMX_EMBEDDED_DEFINE_JOIN_INTEGER(bmx_embedded_string_join_shorts, uint16_t, 0)
BMX_EMBEDDED_DEFINE_JOIN_INTEGER(bmx_embedded_string_join_uints, uint32_t, 0)
BMX_EMBEDDED_DEFINE_JOIN_INTEGER(bmx_embedded_string_join_longs, int64_t, 1)
BMX_EMBEDDED_DEFINE_JOIN_INTEGER(bmx_embedded_string_join_ulongs, uint64_t, 0)
BMX_EMBEDDED_DEFINE_JOIN_INTEGER(bmx_embedded_string_join_sizes, size_t, 0)
BMX_EMBEDDED_DEFINE_JOIN_INTEGER(bmx_embedded_string_join_long_ints, long, 1)
BMX_EMBEDDED_DEFINE_JOIN_INTEGER(bmx_embedded_string_join_ulong_ints, unsigned long, 0)
