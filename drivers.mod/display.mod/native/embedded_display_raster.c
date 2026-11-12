/* Copyright (c) 2026 Bruce A Henderson and contributors
 * SPDX-License-Identifier: Zlib
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>

typedef int32_t (*bmx_embedded_display_fill_rgb565_accelerator_t)(
    uint8_t *pixels, int32_t stride, int32_t buffer_width,
    int32_t buffer_height, int32_t x, int32_t y, int32_t width,
    int32_t height, uint32_t color);

static bmx_embedded_display_fill_rgb565_accelerator_t
    bmx_embedded_display_fill_rgb565_accelerator;

void bmx_embedded_display_set_fill_rgb565_accelerator(
        bmx_embedded_display_fill_rgb565_accelerator_t accelerator) {
    bmx_embedded_display_fill_rgb565_accelerator = accelerator;
}

static void bmx_embedded_display_fill_rgb565_pixels(
        uint16_t *pixels, size_t count, uint16_t color) {
    if (!count) return;
    if (color == 0 || color == UINT16_MAX) {
        memset(pixels, color ? 0xff : 0, count * sizeof(*pixels));
        return;
    }

    if (((uintptr_t)pixels & 2U) != 0U) {
        *pixels++ = color;
        --count;
    }
    const uint32_t pair = (uint32_t)color | ((uint32_t)color << 16);
    uint32_t *wide = (uint32_t *)pixels;
    const size_t pairs = count / 2;
    for (size_t index = 0; index < pairs; ++index) wide[index] = pair;
    if ((count & 1U) != 0U) ((uint16_t *)(wide + pairs))[0] = color;
}

void bmx_embedded_display_fill_rgb565(uint8_t *pixels, int32_t stride,
        int32_t buffer_width, int32_t buffer_height, int32_t x, int32_t y,
        int32_t width, int32_t height, uint32_t color) {
    if (!pixels || stride <= 0 || buffer_width <= 0 || buffer_height <= 0 ||
            x < 0 || y < 0 || width <= 0 || height <= 0) return;
    if (bmx_embedded_display_fill_rgb565_accelerator &&
            bmx_embedded_display_fill_rgb565_accelerator(pixels, stride,
                buffer_width, buffer_height, x, y, width, height, color)) return;
    const uint16_t rgb565 = (uint16_t)((((color >> 19) & 0x1fU) << 11) |
        (((color >> 10) & 0x3fU) << 5) | ((color >> 3) & 0x1fU));
    uint8_t *row = pixels + (size_t)y * (size_t)stride + (size_t)x * 2U;
    if (x == 0 && (size_t)width * 2U == (size_t)stride) {
        bmx_embedded_display_fill_rgb565_pixels((uint16_t *)row,
            (size_t)width * (size_t)height, rgb565);
        return;
    }
    for (int32_t line = 0; line < height; ++line) {
        bmx_embedded_display_fill_rgb565_pixels((uint16_t *)row, (size_t)width, rgb565);
        row += stride;
    }
}
