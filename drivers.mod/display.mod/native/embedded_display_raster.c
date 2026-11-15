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

static void bmx_embedded_display_apply_mono1_mask(
        uint8_t *pixel, uint8_t mask, int set) {
    if (set) {
        *pixel |= mask;
    } else {
        *pixel &= (uint8_t)~mask;
    }
}

static void bmx_embedded_display_fill_mono1_bytes(
        uint8_t *pixels, size_t count, uint8_t value) {
    /* Keep packed writes direct: some embedded libc memset paths impose a
       severe penalty on small or managed-PSRAM spans. */
    volatile uint8_t *destination = pixels;
    for (size_t index = 0; index < count; ++index) destination[index] = value;
}

void bmx_embedded_display_fill_mono1(uint8_t *pixels, int32_t stride,
        int32_t buffer_width, int32_t buffer_height, int32_t x, int32_t y,
        int32_t width, int32_t height, uint32_t color) {
    if (!pixels || stride <= 0 || buffer_width <= 0 || buffer_height <= 0 ||
            x < 0 || y < 0 || width <= 0 || height <= 0 ||
            x > buffer_width - width || y > buffer_height - height) return;

    const int32_t first_byte = x >> 3;
    const int32_t last_x = x + width - 1;
    const int32_t last_byte = last_x >> 3;
    const uint8_t first_mask = (uint8_t)(0xffU >> (x & 7));
    const uint8_t last_mask = (uint8_t)(0xffU << (7 - (last_x & 7)));
    const int set = color != 0;
    uint8_t *row = pixels + (size_t)y * (size_t)stride;

    if (((x | width) & 7) == 0) {
        const size_t byte_width = (size_t)width >> 3;
        row += first_byte;
        if (first_byte == 0 && byte_width == (size_t)stride) {
            bmx_embedded_display_fill_mono1_bytes(row,
                byte_width * (size_t)height, set ? 0xff : 0);
            return;
        }
        for (int32_t line = 0; line < height; ++line) {
            bmx_embedded_display_fill_mono1_bytes(row, byte_width,
                set ? 0xff : 0);
            row += stride;
        }
        return;
    }

    for (int32_t line = 0; line < height; ++line) {
        if (first_byte == last_byte) {
            bmx_embedded_display_apply_mono1_mask(row + first_byte,
                (uint8_t)(first_mask & last_mask), set);
        } else {
            bmx_embedded_display_apply_mono1_mask(row + first_byte,
                first_mask, set);
            if (last_byte > first_byte + 1) {
                bmx_embedded_display_fill_mono1_bytes(row + first_byte + 1,
                    (size_t)(last_byte - first_byte - 1), set ? 0xff : 0);
            }
            bmx_embedded_display_apply_mono1_mask(row + last_byte,
                last_mask, set);
        }
        row += stride;
    }
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

void bmx_embedded_display_draw_line(uint8_t *pixels, int32_t stride,
        int32_t buffer_width, int32_t buffer_height, int32_t format,
        int32_t x0, int32_t y0, int32_t x1, int32_t y1, uint32_t color) {
    if (!pixels || stride <= 0 || buffer_width <= 0 || buffer_height <= 0 ||
            format < 1 || format > 3) return;

    const uint16_t rgb565 = (uint16_t)((((color >> 19) & 0x1fU) << 11) |
        (((color >> 10) & 0x3fU) << 5) | ((color >> 3) & 0x1fU));
    const int32_t dx = x1 >= x0 ? x1 - x0 : x0 - x1;
    const int32_t dy_abs = y1 >= y0 ? y1 - y0 : y0 - y1;
    const int32_t dy = -dy_abs;
    const int32_t sx = x0 < x1 ? 1 : -1;
    const int32_t sy = y0 < y1 ? 1 : -1;
    int32_t error = dx + dy;

    for (;;) {
        if ((uint32_t)x0 < (uint32_t)buffer_width &&
                (uint32_t)y0 < (uint32_t)buffer_height) {
            uint8_t *row = pixels + (size_t)y0 * (size_t)stride;
            if (format == 1) {
                uint8_t *pixel = row + (x0 >> 3);
                const uint8_t mask = (uint8_t)(0x80U >> (x0 & 7));
                if (color) *pixel |= mask;
                else *pixel &= (uint8_t)~mask;
            } else if (format == 2) {
                uint8_t *pixel = row + (size_t)x0 * 2U;
                pixel[0] = (uint8_t)rgb565;
                pixel[1] = (uint8_t)(rgb565 >> 8);
            } else {
                uint8_t *pixel = row + (size_t)x0 * 3U;
                pixel[0] = (uint8_t)(color >> 16);
                pixel[1] = (uint8_t)(color >> 8);
                pixel[2] = (uint8_t)color;
            }
        }
        if (x0 == x1 && y0 == y1) break;
        const int32_t twice_error = error * 2;
        if (twice_error >= dy) {
            error += dy;
            x0 += sx;
        }
        if (twice_error <= dx) {
            error += dx;
            y0 += sy;
        }
    }
}
