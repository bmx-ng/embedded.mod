/* Copyright (c) 2026 Bruce A Henderson and contributors
 * SPDX-License-Identifier: Zlib
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <math.h>

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

void bmx_embedded_display_draw_rect(uint8_t *pixels, int32_t stride,
        int32_t buffer_width, int32_t buffer_height, int32_t format,
        int32_t x, int32_t y, int32_t width, int32_t height,
        uint32_t color) {
    if (!pixels || stride <= 0 || buffer_width <= 0 || buffer_height <= 0 ||
            format < 1 || format > 3 || width <= 0 || height <= 0) return;

    const int32_t right = x + width - 1;
    const int32_t bottom = y + height - 1;
    int32_t span_x = x;
    int32_t span_right = right;
    if (span_x < 0) span_x = 0;
    if (span_right >= buffer_width) span_right = buffer_width - 1;
    if (span_x <= span_right) {
        if ((uint32_t)y < (uint32_t)buffer_height) {
            if (format == 1) {
                bmx_embedded_display_fill_mono1(pixels, stride, buffer_width,
                    buffer_height, span_x, y, span_right - span_x + 1, 1, color);
            } else if (format == 2) {
                bmx_embedded_display_fill_rgb565(pixels, stride, buffer_width,
                    buffer_height, span_x, y, span_right - span_x + 1, 1, color);
            } else {
                const uint8_t red = (uint8_t)(color >> 16);
                const uint8_t green = (uint8_t)(color >> 8);
                const uint8_t blue = (uint8_t)color;
                uint8_t *output = pixels + (size_t)y * (size_t)stride +
                    (size_t)span_x * 3U;
                for (int32_t column = span_x; column <= span_right; ++column) {
                    *output++ = red;
                    *output++ = green;
                    *output++ = blue;
                }
            }
        }
        if (bottom != y && (uint32_t)bottom < (uint32_t)buffer_height) {
            if (format == 1) {
                bmx_embedded_display_fill_mono1(pixels, stride, buffer_width,
                    buffer_height, span_x, bottom, span_right - span_x + 1, 1, color);
            } else if (format == 2) {
                bmx_embedded_display_fill_rgb565(pixels, stride, buffer_width,
                    buffer_height, span_x, bottom, span_right - span_x + 1, 1, color);
            } else {
                const uint8_t red = (uint8_t)(color >> 16);
                const uint8_t green = (uint8_t)(color >> 8);
                const uint8_t blue = (uint8_t)color;
                uint8_t *output = pixels + (size_t)bottom * (size_t)stride +
                    (size_t)span_x * 3U;
                for (int32_t column = span_x; column <= span_right; ++column) {
                    *output++ = red;
                    *output++ = green;
                    *output++ = blue;
                }
            }
        }
    }

    int32_t span_y = y;
    int32_t span_bottom = bottom;
    if (span_y < 0) span_y = 0;
    if (span_bottom >= buffer_height) span_bottom = buffer_height - 1;
    if (span_y > span_bottom) return;
    const uint16_t rgb565 = (uint16_t)((((color >> 19) & 0x1fU) << 11) |
        (((color >> 10) & 0x3fU) << 5) | ((color >> 3) & 0x1fU));
    const uint8_t mono_mask_left = (uint8_t)(0x80U >> (x & 7));
    const uint8_t mono_mask_right = (uint8_t)(0x80U >> (right & 7));
    for (int32_t row = span_y; row <= span_bottom; ++row) {
        uint8_t *output = pixels + (size_t)row * (size_t)stride;
        if ((uint32_t)x < (uint32_t)buffer_width) {
            if (format == 1) {
                if (color) output[x >> 3] |= mono_mask_left;
                else output[x >> 3] &= (uint8_t)~mono_mask_left;
            } else if (format == 2) {
                output += (size_t)x * 2U;
                output[0] = (uint8_t)rgb565;
                output[1] = (uint8_t)(rgb565 >> 8);
            } else {
                output += (size_t)x * 3U;
                output[0] = (uint8_t)(color >> 16);
                output[1] = (uint8_t)(color >> 8);
                output[2] = (uint8_t)color;
            }
        }
        if (right != x && (uint32_t)right < (uint32_t)buffer_width) {
            output = pixels + (size_t)row * (size_t)stride;
            if (format == 1) {
                if (color) output[right >> 3] |= mono_mask_right;
                else output[right >> 3] &= (uint8_t)~mono_mask_right;
            } else if (format == 2) {
                output += (size_t)right * 2U;
                output[0] = (uint8_t)rgb565;
                output[1] = (uint8_t)(rgb565 >> 8);
            } else {
                output += (size_t)right * 3U;
                output[0] = (uint8_t)(color >> 16);
                output[1] = (uint8_t)(color >> 8);
                output[2] = (uint8_t)color;
            }
        }
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

static void bmx_embedded_display_write_pixel(uint8_t *pixels, int32_t stride,
        int32_t format, int32_t x, int32_t y, uint32_t color,
        uint16_t rgb565) {
    uint8_t *row = pixels + (size_t)y * (size_t)stride;
    if (format == 1) {
        uint8_t *pixel = row + (x >> 3);
        const uint8_t mask = (uint8_t)(0x80U >> (x & 7));
        if (color) *pixel |= mask;
        else *pixel &= (uint8_t)~mask;
    } else if (format == 2) {
        uint8_t *pixel = row + (size_t)x * 2U;
        pixel[0] = (uint8_t)rgb565;
        pixel[1] = (uint8_t)(rgb565 >> 8);
    } else {
        uint8_t *pixel = row + (size_t)x * 3U;
        pixel[0] = (uint8_t)(color >> 16);
        pixel[1] = (uint8_t)(color >> 8);
        pixel[2] = (uint8_t)color;
    }
}

static void bmx_embedded_display_write_clipped_pixel(uint8_t *pixels,
        int32_t stride, int32_t format, int32_t x, int32_t y,
        int32_t clip_x, int32_t clip_y, int32_t clip_x1, int32_t clip_y1,
        uint32_t color, uint16_t rgb565) {
    if (x < clip_x || x >= clip_x1 || y < clip_y || y >= clip_y1) return;
    bmx_embedded_display_write_pixel(pixels, stride, format, x, y, color,
        rgb565);
}

static void bmx_embedded_display_draw_clipped_line(uint8_t *pixels,
        int32_t stride, int32_t format, int32_t x0, int32_t y0,
        int32_t x1, int32_t y1, int32_t clip_x, int32_t clip_y,
        int32_t clip_x1, int32_t clip_y1, uint32_t color, uint16_t rgb565) {
    const int32_t dx = x1 >= x0 ? x1 - x0 : x0 - x1;
    const int32_t dy_abs = y1 >= y0 ? y1 - y0 : y0 - y1;
    const int32_t dy = -dy_abs;
    const int32_t sx = x0 < x1 ? 1 : -1;
    const int32_t sy = y0 < y1 ? 1 : -1;
    int32_t error = dx + dy;
    for (;;) {
        bmx_embedded_display_write_clipped_pixel(pixels, stride, format,
            x0, y0, clip_x, clip_y, clip_x1, clip_y1, color, rgb565);
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

void bmx_embedded_display_draw_circle(uint8_t *pixels, int32_t stride,
        int32_t buffer_width, int32_t buffer_height, int32_t format,
        int32_t center_x, int32_t center_y, int32_t radius,
        int32_t clip_x, int32_t clip_y, int32_t clip_width,
        int32_t clip_height, uint32_t color) {
    if (!pixels || stride <= 0 || buffer_width <= 0 || buffer_height <= 0 ||
            format < 1 || format > 3 || radius < 0 || clip_x < 0 ||
            clip_y < 0 || clip_width <= 0 || clip_height <= 0 ||
            clip_x + clip_width > buffer_width ||
            clip_y + clip_height > buffer_height) return;

    const int32_t clip_x1 = clip_x + clip_width;
    const int32_t clip_y1 = clip_y + clip_height;
    const uint16_t rgb565 = (uint16_t)((((color >> 19) & 0x1fU) << 11) |
        (((color >> 10) & 0x3fU) << 5) | ((color >> 3) & 0x1fU));
    int32_t x = radius;
    int32_t y = 0;
    int32_t error = 1 - radius;
    while (x >= y) {
        bmx_embedded_display_write_clipped_pixel(pixels, stride, format,
            center_x + x, center_y + y, clip_x, clip_y, clip_x1, clip_y1,
            color, rgb565);
        bmx_embedded_display_write_clipped_pixel(pixels, stride, format,
            center_x + y, center_y + x, clip_x, clip_y, clip_x1, clip_y1,
            color, rgb565);
        bmx_embedded_display_write_clipped_pixel(pixels, stride, format,
            center_x - y, center_y + x, clip_x, clip_y, clip_x1, clip_y1,
            color, rgb565);
        bmx_embedded_display_write_clipped_pixel(pixels, stride, format,
            center_x - x, center_y + y, clip_x, clip_y, clip_x1, clip_y1,
            color, rgb565);
        bmx_embedded_display_write_clipped_pixel(pixels, stride, format,
            center_x - x, center_y - y, clip_x, clip_y, clip_x1, clip_y1,
            color, rgb565);
        bmx_embedded_display_write_clipped_pixel(pixels, stride, format,
            center_x - y, center_y - x, clip_x, clip_y, clip_x1, clip_y1,
            color, rgb565);
        bmx_embedded_display_write_clipped_pixel(pixels, stride, format,
            center_x + y, center_y - x, clip_x, clip_y, clip_x1, clip_y1,
            color, rgb565);
        bmx_embedded_display_write_clipped_pixel(pixels, stride, format,
            center_x + x, center_y - y, clip_x, clip_y, clip_x1, clip_y1,
            color, rgb565);
        ++y;
        if (error < 0) {
            error += 2 * y + 1;
        } else {
            --x;
            error += 2 * (y - x + 1);
        }
    }
}

static void bmx_embedded_display_fill_clipped_span(uint8_t *pixels,
        int32_t stride, int32_t buffer_width, int32_t buffer_height,
        int32_t format, int32_t x0, int32_t x1, int32_t y,
        int32_t clip_x, int32_t clip_y, int32_t clip_x1, int32_t clip_y1,
        uint32_t color) {
    if (y < clip_y || y >= clip_y1) return;
    if (x0 < clip_x) x0 = clip_x;
    if (x1 >= clip_x1) x1 = clip_x1 - 1;
    if (x0 > x1) return;
    const int32_t width = x1 - x0 + 1;
    if (format == 1) {
        bmx_embedded_display_fill_mono1(pixels, stride, buffer_width,
            buffer_height, x0, y, width, 1, color);
    } else if (format == 2) {
        bmx_embedded_display_fill_rgb565(pixels, stride, buffer_width,
            buffer_height, x0, y, width, 1, color);
    } else {
        const uint16_t unused_rgb565 = 0;
        for (int32_t x = x0; x <= x1; ++x) {
            bmx_embedded_display_write_pixel(pixels, stride, format, x, y,
                color, unused_rgb565);
        }
    }
}

void bmx_embedded_display_fill_circle(uint8_t *pixels, int32_t stride,
        int32_t buffer_width, int32_t buffer_height, int32_t format,
        int32_t center_x, int32_t center_y, int32_t radius,
        int32_t clip_x, int32_t clip_y, int32_t clip_width,
        int32_t clip_height, uint32_t color) {
    if (!pixels || stride <= 0 || buffer_width <= 0 || buffer_height <= 0 ||
            format < 1 || format > 3 || radius < 0 || clip_x < 0 ||
            clip_y < 0 || clip_width <= 0 || clip_height <= 0 ||
            clip_x + clip_width > buffer_width ||
            clip_y + clip_height > buffer_height) return;

    const int32_t clip_x1 = clip_x + clip_width;
    const int32_t clip_y1 = clip_y + clip_height;
    const int64_t radius_squared = (int64_t)radius * radius;
    int32_t extent = 0;
    for (int32_t offset = radius; offset >= 0; --offset) {
        while (extent < radius &&
                (int64_t)(extent + 1) * (extent + 1) +
                (int64_t)offset * offset <= radius_squared) ++extent;
        bmx_embedded_display_fill_clipped_span(pixels, stride, buffer_width,
            buffer_height, format, center_x - extent, center_x + extent,
            center_y - offset, clip_x, clip_y, clip_x1, clip_y1, color);
        if (offset) {
            bmx_embedded_display_fill_clipped_span(pixels, stride, buffer_width,
                buffer_height, format, center_x - extent, center_x + extent,
                center_y + offset, clip_x, clip_y, clip_x1, clip_y1, color);
        }
    }
}

void bmx_embedded_display_draw_arc(uint8_t *pixels, int32_t stride,
        int32_t buffer_width, int32_t buffer_height, int32_t format,
        int32_t center_x, int32_t center_y, int32_t radius,
        int32_t start_degrees, int32_t sweep_degrees, int32_t line_width,
        int32_t clip_x, int32_t clip_y, int32_t clip_width,
        int32_t clip_height, uint32_t color) {
    if (!pixels || stride <= 0 || buffer_width <= 0 || buffer_height <= 0 ||
            format < 1 || format > 3 || radius <= 0 || sweep_degrees == 0 ||
            line_width <= 0 || clip_x < 0 || clip_y < 0 || clip_width <= 0 ||
            clip_height <= 0 || clip_x + clip_width > buffer_width ||
            clip_y + clip_height > buffer_height) return;
    if (line_width > radius) line_width = radius;

    const int32_t clip_x1 = clip_x + clip_width;
    const int32_t clip_y1 = clip_y + clip_height;
    const uint16_t rgb565 = (uint16_t)((((color >> 19) & 0x1fU) << 11) |
        (((color >> 10) & 0x3fU) << 5) | ((color >> 3) & 0x1fU));
    const int32_t absolute_sweep = sweep_degrees < 0 ? -sweep_degrees : sweep_degrees;
    const int32_t segment_count = absolute_sweep / 5 > 0 ? absolute_sweep / 5 : 1;
    const double degrees_to_radians = 0.01745329251994329576923690768489;

    double angle = (double)start_degrees * degrees_to_radians;
    double previous_cosine = cos(angle);
    double previous_sine = sin(angle);
    for (int32_t segment = 1; segment <= segment_count; ++segment) {
        angle = ((double)start_degrees + (double)sweep_degrees *
            (double)segment / (double)segment_count) * degrees_to_radians;
        const double cosine = cos(angle);
        const double sine = sin(angle);
        for (int32_t ring = 0; ring < line_width; ++ring) {
            const int32_t ring_radius = radius - ring;
            double value = previous_cosine * (double)ring_radius;
            const int32_t previous_x = center_x +
                (int32_t)(value >= 0.0 ? value + 0.5 : value - 0.5);
            value = previous_sine * (double)ring_radius;
            const int32_t previous_y = center_y +
                (int32_t)(value >= 0.0 ? value + 0.5 : value - 0.5);
            value = cosine * (double)ring_radius;
            const int32_t x = center_x +
                (int32_t)(value >= 0.0 ? value + 0.5 : value - 0.5);
            value = sine * (double)ring_radius;
            const int32_t y = center_y +
                (int32_t)(value >= 0.0 ? value + 0.5 : value - 0.5);
            bmx_embedded_display_draw_clipped_line(pixels, stride, format,
                previous_x, previous_y, x, y, clip_x, clip_y, clip_x1,
                clip_y1, color, rgb565);
        }
        previous_cosine = cosine;
        previous_sine = sine;
    }
}

void bmx_embedded_display_draw_mono1_mask(uint8_t *pixels, int32_t stride,
        int32_t buffer_width, int32_t buffer_height, int32_t format,
        const uint8_t *mask, int32_t mask_stride, int32_t mask_width,
        int32_t mask_height, int32_t x, int32_t y, int32_t scale,
        int32_t clip_x, int32_t clip_y, int32_t clip_width,
        int32_t clip_height, uint32_t color) {
    if (!pixels || !mask || stride <= 0 || buffer_width <= 0 ||
            buffer_height <= 0 || format < 1 || format > 3 ||
            mask_width <= 0 || mask_height <= 0 ||
            mask_stride < (mask_width + 7) / 8 || scale <= 0 ||
            clip_x < 0 || clip_y < 0 || clip_width <= 0 || clip_height <= 0 ||
            clip_x + clip_width > buffer_width ||
            clip_y + clip_height > buffer_height) return;

    const int32_t clip_x1 = clip_x + clip_width;
    const int32_t clip_y1 = clip_y + clip_height;
    const uint16_t rgb565 = (uint16_t)((((color >> 19) & 0x1fU) << 11) |
        (((color >> 10) & 0x3fU) << 5) | ((color >> 3) & 0x1fU));

    /* Small bitmap fonts overwhelmingly use an unscaled RGB565 mask. Keep
       that hot path free of run detection, generic scale loops, and per-pixel
       format tests. */
    if (format == 2 && scale == 1) {
        int32_t first_column = clip_x - x;
        int32_t last_column = clip_x1 - x;
        if (first_column < 0) first_column = 0;
        if (last_column > mask_width) last_column = mask_width;
        if (first_column >= last_column) return;

        for (int32_t row = 0; row < mask_height; ++row) {
            const int32_t output_y = y + row;
            if (output_y < clip_y || output_y >= clip_y1) continue;
            const uint8_t *mask_row = mask + (size_t)row * (size_t)mask_stride;
            uint8_t *output = pixels + (size_t)output_y * (size_t)stride +
                (size_t)(x + first_column) * 2U;
            for (int32_t column = first_column; column < last_column; ++column) {
                if (mask_row[column >> 3] &
                        (uint8_t)(0x80U >> (column & 7))) {
                    output[0] = (uint8_t)rgb565;
                    output[1] = (uint8_t)(rgb565 >> 8);
                }
                output += 2;
            }
        }
        return;
    }

    /* Convert scaled RGB565 mask rows into horizontal runs so enlarged glyphs
       use wide fills instead of the generic per-destination-pixel path. */
    if (format == 2) {
        for (int32_t row = 0; row < mask_height; ++row) {
            const int32_t output_y = y + row * scale;
            if (output_y >= clip_y1 || output_y + scale <= clip_y) continue;
            const uint8_t *mask_row = mask + (size_t)row * (size_t)mask_stride;
            int32_t first_y = output_y < clip_y ? clip_y : output_y;
            int32_t last_y = output_y + scale;
            if (last_y > clip_y1) last_y = clip_y1;
            int32_t column = 0;
            while (column < mask_width) {
                while (column < mask_width && !(mask_row[column >> 3] &
                        (uint8_t)(0x80U >> (column & 7)))) ++column;
                const int32_t run_start = column;
                while (column < mask_width && (mask_row[column >> 3] &
                        (uint8_t)(0x80U >> (column & 7)))) ++column;
                if (run_start == column) break;
                int32_t first_x = x + run_start * scale;
                int32_t last_x = x + column * scale;
                if (first_x < clip_x) first_x = clip_x;
                if (last_x > clip_x1) last_x = clip_x1;
                if (first_x >= last_x) continue;
                for (int32_t py = first_y; py < last_y; ++py) {
                    uint8_t *output = pixels + (size_t)py * (size_t)stride +
                        (size_t)first_x * 2U;
                    bmx_embedded_display_fill_rgb565_pixels((uint16_t *)output,
                        (size_t)(last_x - first_x), rgb565);
                }
            }
        }
        return;
    }

    for (int32_t row = 0; row < mask_height; ++row) {
        const int32_t output_y = y + row * scale;
        if (output_y >= clip_y1 || output_y + scale <= clip_y) continue;
        const uint8_t *mask_row = mask + (size_t)row * (size_t)mask_stride;
        for (int32_t column = 0; column < mask_width; ++column) {
            if (!(mask_row[column >> 3] & (uint8_t)(0x80U >> (column & 7)))) continue;
            const int32_t output_x = x + column * scale;
            if (output_x >= clip_x1 || output_x + scale <= clip_x) continue;
            int32_t first_y = output_y < clip_y ? clip_y : output_y;
            int32_t last_y = output_y + scale;
            if (last_y > clip_y1) last_y = clip_y1;
            int32_t first_x = output_x < clip_x ? clip_x : output_x;
            int32_t last_x = output_x + scale;
            if (last_x > clip_x1) last_x = clip_x1;
            for (int32_t py = first_y; py < last_y; ++py) {
                for (int32_t px = first_x; px < last_x; ++px) {
                    bmx_embedded_display_write_pixel(pixels, stride, format,
                        px, py, color, rgb565);
                }
            }
        }
    }
}
