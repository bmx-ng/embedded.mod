#include <cstdint>
#include <cstdio>
#include <cstring>
#include <climits>
#include <system_error>

#include "blitzmax/embedded_runtime.h"
#include "fast_float/fast_float.h"
#include "ryu/ryu.h"

extern "C" int __real_snprintf(char *buffer, size_t count, const char *format, ...);

static int bmx_embedded_expand_ryu(const char *input, int length, char *output, int minimum, int maximum) {
    int exponent_at = -1;
    for (int index = 0; index < length; ++index) {
        if (input[index] == 'E' || input[index] == 'e') {
            exponent_at = index;
            break;
        }
    }
    if (exponent_at < 0) return 0;
    int cursor = exponent_at + 1;
    int negative_exponent = 0;
    if (cursor < length && (input[cursor] == '+' || input[cursor] == '-')) {
        negative_exponent = input[cursor] == '-';
        ++cursor;
    }
    int exponent = 0;
    int digits_seen = 0;
    for (; cursor < length; ++cursor) {
        if (input[cursor] < '0' || input[cursor] > '9') return 0;
        digits_seen = 1;
        exponent = exponent * 10 + input[cursor] - '0';
        if (exponent > 1000) return 0;
    }
    if (!digits_seen) return 0;
    if (negative_exponent) exponent = -exponent;
    if (exponent < minimum || exponent > maximum) return 0;

    char digits[64];
    int input_at = 0;
    int output_at = 0;
    if (input[0] == '-') {
        output[output_at++] = '-';
        input_at = 1;
    }
    int digit_count = 0;
    int decimal_at = -1;
    for (; input_at < exponent_at; ++input_at) {
        if (input[input_at] == '.') decimal_at = digit_count;
        else digits[digit_count++] = input[input_at];
    }
    if (!digit_count) return 0;
    if (decimal_at < 0) decimal_at = digit_count;
    const int decimal_position = decimal_at + exponent;
    int wrote_decimal = 0;
    if (decimal_position <= 0) {
        output[output_at++] = '0';
        output[output_at++] = '.';
        wrote_decimal = 1;
        for (int zeros = -decimal_position; zeros; --zeros) {
            if (output_at >= 63) return 0;
            output[output_at++] = '0';
        }
        for (int index = 0; index < digit_count; ++index) {
            if (output_at >= 63) return 0;
            output[output_at++] = digits[index];
        }
    } else if (decimal_position >= digit_count) {
        for (int index = 0; index < digit_count; ++index) output[output_at++] = digits[index];
        for (int zeros = decimal_position - digit_count; zeros; --zeros) {
            if (output_at >= 63) return 0;
            output[output_at++] = '0';
        }
    } else {
        for (int index = 0; index < digit_count; ++index) {
            if (index == decimal_position) {
                output[output_at++] = '.';
                wrote_decimal = 1;
            }
            output[output_at++] = digits[index];
        }
    }
    if (!wrote_decimal) {
        if (output_at + 2 >= 64) return 0;
        output[output_at++] = '.';
        output[output_at++] = '0';
    }
    for (int index = 0; index < output_at; ++index) {
        if (output[index] != '.') continue;
        while (output_at > index + 2 && output[output_at - 1] == '0') --output_at;
        break;
    }
    return output_at;
}

static int bmx_embedded_float_text(float value, char *buffer) {
    int length = f2s_buffered_n(value, buffer);
    if (length <= 0) return length;
    char expanded[64];
    int expanded_length = bmx_embedded_expand_ryu(buffer, length, expanded, -3, 7);
    if (expanded_length) std::memcpy(buffer, expanded, (size_t)expanded_length);
    return expanded_length ? expanded_length : length;
}

static int bmx_embedded_double_text(double value, char *buffer) {
    int length = d2s_buffered_n(value, buffer);
    if (length <= 0) return length;
    char expanded[64];
    int expanded_length = bmx_embedded_expand_ryu(buffer, length, expanded, -6, 15);
    if (expanded_length) std::memcpy(buffer, expanded, (size_t)expanded_length);
    return expanded_length ? expanded_length : length;
}

extern "C" const BMXEmbeddedString *bmx_embedded_string_from_float_default(float value) {
    char buffer[350];
    int length = bmx_embedded_float_text(value, buffer);
    return length > 0 ? bmx_embedded_string_from_ascii(buffer, length) : &bmx_embedded_empty_string;
}

extern "C" const BMXEmbeddedString *bmx_embedded_string_from_double_default(double value) {
    char buffer[350];
    int length = bmx_embedded_double_text(value, buffer);
    return length > 0 ? bmx_embedded_string_from_ascii(buffer, length) : &bmx_embedded_empty_string;
}

extern "C" const BMXEmbeddedString *bmx_embedded_string_from_float_fixed(float value) {
    char buffer[350];
    int length = __real_snprintf(buffer, sizeof(buffer), "%.9f", (double)value);
    return length > 0 ? bmx_embedded_string_from_ascii(buffer, length) : &bmx_embedded_empty_string;
}

extern "C" const BMXEmbeddedString *bmx_embedded_string_from_double_fixed(double value) {
    char buffer[350];
    int length = __real_snprintf(buffer, sizeof(buffer), "%.17f", value);
    return length > 0 ? bmx_embedded_string_from_ascii(buffer, length) : &bmx_embedded_empty_string;
}

template<typename Number>
static Number bmx_embedded_string_parse_float_range(const uint16_t *characters, int32_t length,
    int32_t *end_index = nullptr) {
    if (!characters) return 0;
    int32_t index = 0;
    while (index < length && (characters[index] == ' ' || (characters[index] >= '\t' && characters[index] <= '\r'))) ++index;
    if (index < length && characters[index] == '+') ++index;
    const char16_t *first = reinterpret_cast<const char16_t *>(characters + index);
    const char16_t *last = reinterpret_cast<const char16_t *>(characters + length);
    Number value = 0;
    fast_float::from_chars_result_t<char16_t> result = fast_float::from_chars(first, last, value, fast_float::chars_format::general);
    if (end_index) *end_index = index + static_cast<int32_t>(result.ptr - first);
    return result.ec == std::errc() ? value : 0;
}

template<typename Number>
static Number bmx_embedded_string_parse_float(const BMXEmbeddedString *text) {
    return text ? bmx_embedded_string_parse_float_range<Number>(text->buf, text->length) : 0;
}

extern "C" float bmx_embedded_string_to_float(const BMXEmbeddedString *text) {
    return bmx_embedded_string_parse_float<float>(text);
}

extern "C" double bmx_embedded_string_to_double(const BMXEmbeddedString *text) {
    return bmx_embedded_string_parse_float<double>(text);
}

static bool bmx_embedded_float_space(uint16_t character) {
    return character == ' ' || (character >= '\t' && character <= '\r');
}

static bool bmx_embedded_float_separator_matches(const BMXEmbeddedString *text, int32_t at,
    const BMXEmbeddedString *separator) {
    for (int32_t index = 0; index < separator->length; ++index) {
        if (text->buf[at + index] != separator->buf[index]) return false;
    }
    return true;
}

static int32_t bmx_embedded_float_part_count(const BMXEmbeddedString *text, const BMXEmbeddedString *separator) {
    if (!text || !text->length) return 0;
    if (!separator || !separator->length) return 1;
    int32_t count = 1;
    for (int32_t index = 0; index <= text->length - separator->length;) {
        if (bmx_embedded_float_separator_matches(text, index, separator)) {
            if (count == INT32_MAX) return 0;
            ++count;
            index += separator->length;
        } else {
            ++index;
        }
    }
    return count;
}

template<typename Number>
static Number bmx_embedded_parse_float_part(const uint16_t *characters, int32_t length) {
    if (length <= 0) return 0;
    int32_t end = 0;
    Number value = bmx_embedded_string_parse_float_range<Number>(characters, length, &end);
    while (end < length && bmx_embedded_float_space(characters[end])) ++end;
    return end == length ? value : 0;
}

template<typename Number>
static BMXEmbeddedArray *bmx_embedded_split_floats(const BMXEmbeddedString *text, const BMXEmbeddedString *separator) {
    int32_t count = bmx_embedded_float_part_count(text, separator);
    if (!count) return &bmx_embedded_empty_array;
    BMXEmbeddedArray *result = bmx_embedded_array_new_1d(count, static_cast<uint32_t>(sizeof(Number)),
        BMX_EMBEDDED_ARRAY_ELEMENT_VALUE, nullptr, nullptr);
    if (result == &bmx_embedded_empty_array) return result;
    Number *output = static_cast<Number *>(bmx_embedded_array_data(result));
    if (!separator || !separator->length) {
        output[0] = bmx_embedded_parse_float_part<Number>(text->buf, text->length);
        return result;
    }
    int32_t begin = 0;
    int32_t part = 0;
    for (int32_t index = 0; index <= text->length;) {
        bool match = index <= text->length - separator->length &&
            bmx_embedded_float_separator_matches(text, index, separator);
        if (match || index == text->length) {
            output[part++] = bmx_embedded_parse_float_part<Number>(text->buf + begin, index - begin);
            if (index == text->length) break;
            index += separator->length;
            begin = index;
        } else {
            ++index;
        }
    }
    return result;
}

extern "C" BMXEmbeddedArray *bmx_embedded_string_split_floats(const BMXEmbeddedString *text,
    const BMXEmbeddedString *separator) {
    return bmx_embedded_split_floats<float>(text, separator);
}

extern "C" BMXEmbeddedArray *bmx_embedded_string_split_doubles(const BMXEmbeddedString *text,
    const BMXEmbeddedString *separator) {
    return bmx_embedded_split_floats<double>(text, separator);
}

static int bmx_embedded_float_fixed_text(float value, char *buffer) {
    return __real_snprintf(buffer, 350, "%.9f", static_cast<double>(value));
}

static int bmx_embedded_double_fixed_text(double value, char *buffer) {
    return __real_snprintf(buffer, 350, "%.17f", value);
}

template<typename Number, typename Formatter>
static const BMXEmbeddedString *bmx_embedded_join_floats(const BMXEmbeddedString *separator,
    BMXEmbeddedArray *values, Formatter formatter) {
    if (!separator) separator = &bmx_embedded_empty_string;
    if (!values || values == &bmx_embedded_empty_array || !values->length) return &bmx_embedded_empty_string;
    if (values->element_kind != BMX_EMBEDDED_ARRAY_ELEMENT_VALUE || values->element_size != sizeof(Number)) {
        return &bmx_embedded_empty_string;
    }
    const Number *data = static_cast<const Number *>(bmx_embedded_array_data(values));
    int64_t total = static_cast<int64_t>(values->length - 1) * separator->length;
    char buffer[350];
    for (int32_t index = 0; index < values->length; ++index) {
        int length = formatter(data[index], buffer);
        if (length > 0) total += length;
        if (total > INT32_MAX) return &bmx_embedded_empty_string;
    }
    BMXEmbeddedString *result = bmx_embedded_string_allocate(static_cast<int32_t>(total));
    if (result == &bmx_embedded_empty_string) return result;
    uint16_t *output = const_cast<uint16_t *>(result->buf);
    for (int32_t index = 0; index < values->length; ++index) {
        if (index && separator->length) {
            std::memcpy(output, separator->buf, static_cast<size_t>(separator->length) * sizeof(uint16_t));
            output += separator->length;
        }
        int length = formatter(data[index], buffer);
        for (int offset = 0; offset < length; ++offset) *output++ = static_cast<uint8_t>(buffer[offset]);
    }
    return result;
}

extern "C" const BMXEmbeddedString *bmx_embedded_string_join_floats_default(const BMXEmbeddedString *separator,
    BMXEmbeddedArray *values) {
    return bmx_embedded_join_floats<float>(separator, values, bmx_embedded_float_text);
}

extern "C" const BMXEmbeddedString *bmx_embedded_string_join_floats_fixed(const BMXEmbeddedString *separator,
    BMXEmbeddedArray *values) {
    return bmx_embedded_join_floats<float>(separator, values, bmx_embedded_float_fixed_text);
}

extern "C" const BMXEmbeddedString *bmx_embedded_string_join_doubles_default(const BMXEmbeddedString *separator,
    BMXEmbeddedArray *values) {
    return bmx_embedded_join_floats<double>(separator, values, bmx_embedded_double_text);
}

extern "C" const BMXEmbeddedString *bmx_embedded_string_join_doubles_fixed(const BMXEmbeddedString *separator,
    BMXEmbeddedArray *values) {
    return bmx_embedded_join_floats<double>(separator, values, bmx_embedded_double_fixed_text);
}
