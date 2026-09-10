#include <stdint.h>
#include <string.h>

#include "blitzmax/embedded_runtime.h"

#define BB_UNICODE_CASE_TABLE_QUALIFIER static const
#define bbToLowerData bmx_embedded_to_lower_data
#define bbToUpperData bmx_embedded_to_upper_data
#define bbFoldCharLUT bmx_embedded_unicode_fold_character
#include "blitz_unicode.c"

static uint16_t bmx_embedded_unicode_map(uint16_t character, const uint16_t *pairs, uint32_t pair_count) {
    uint32_t low = 0;
    uint32_t high = pair_count;
    while (low < high) {
        uint32_t middle = low + (high - low) / 2u;
        uint16_t source = pairs[middle * 2u];
        if (character < source) high = middle;
        else if (character > source) low = middle + 1u;
        else return pairs[middle * 2u + 1u];
    }
    return character;
}

static uint16_t bmx_embedded_unicode_lower_character(uint16_t character) {
    if (character >= (uint16_t)'A' && character <= (uint16_t)'Z') {
        return character + ((uint16_t)'a' - (uint16_t)'A');
    }
    return bmx_embedded_unicode_map(character, bmx_embedded_to_lower_data,
        (uint32_t)(sizeof(bmx_embedded_to_lower_data) / (2u * sizeof(uint16_t))));
}

static uint16_t bmx_embedded_unicode_upper_character(uint16_t character) {
    if (character >= (uint16_t)'a' && character <= (uint16_t)'z') {
        return character - ((uint16_t)'a' - (uint16_t)'A');
    }
    return bmx_embedded_unicode_map(character, bmx_embedded_to_upper_data,
        (uint32_t)(sizeof(bmx_embedded_to_upper_data) / (2u * sizeof(uint16_t))));
}

static const BMXEmbeddedString *bmx_embedded_unicode_transform(const BMXEmbeddedString *text,
    uint16_t (*mapper)(uint16_t)) {
    if (!text || !text->length) return &bmx_embedded_empty_string;
    int32_t first_change = 0;
    while (first_change < text->length && mapper(text->buf[first_change]) == text->buf[first_change]) {
        ++first_change;
    }
    if (first_change == text->length) return text;
    BMXEmbeddedString *result = bmx_embedded_string_allocate(text->length);
    if (result == &bmx_embedded_empty_string) return result;
    uint16_t *output = (uint16_t *)(uintptr_t)result->buf;
    if (first_change) {
        memcpy(output, text->buf, (size_t)first_change * sizeof(uint16_t));
    }
    for (int32_t index = first_change; index < text->length; ++index) {
        output[index] = mapper(text->buf[index]);
    }
    return result;
}

static const BMXEmbeddedString *bmx_embedded_unicode_to_lower(const BMXEmbeddedString *text) {
    return bmx_embedded_unicode_transform(text, bmx_embedded_unicode_lower_character);
}

static const BMXEmbeddedString *bmx_embedded_unicode_to_upper(const BMXEmbeddedString *text) {
    return bmx_embedded_unicode_transform(text, bmx_embedded_unicode_upper_character);
}

void bmx_embedded_unicode_enable(void) {
    bmx_embedded_string_install_unicode_case(bmx_embedded_unicode_to_lower, bmx_embedded_unicode_to_upper,
        bmx_embedded_unicode_fold_character);
}
