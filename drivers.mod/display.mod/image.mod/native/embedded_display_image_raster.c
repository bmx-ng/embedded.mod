/* Copyright (c) 2026 Bruce A Henderson and contributors
 * SPDX-License-Identifier: Zlib
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define BMX_EMBEDDED_IMAGE_FLIP_X 1
#define BMX_EMBEDDED_IMAGE_FLIP_Y 2
#define BMX_DISPLAY_PIXEL_FORMAT_MONO1 1
#define BMX_DISPLAY_PIXEL_FORMAT_RGB565 2
#define BMX_DISPLAY_PIXEL_FORMAT_RGB888 3

typedef int32_t (*bmx_embedded_display_blit_rgb565_accelerator_t)(
    uint8_t *target, int32_t target_stride, int32_t target_width,
    int32_t target_height, const uint8_t *source, int32_t source_stride,
    int32_t source_width, int32_t source_height, int32_t source_format,
    int32_t destination_x, int32_t destination_y, int32_t destination_width,
    int32_t destination_height, int32_t clip_x, int32_t clip_y,
    int32_t clip_width, int32_t clip_height, uint32_t tint,
    int32_t opacity, int32_t draw_flags);

static bmx_embedded_display_blit_rgb565_accelerator_t
    bmx_embedded_display_blit_rgb565_accelerator;

void bmx_embedded_display_set_blit_rgb565_accelerator(
        bmx_embedded_display_blit_rgb565_accelerator_t accelerator) {
    bmx_embedded_display_blit_rgb565_accelerator = accelerator;
}

int32_t bmx_embedded_display_blit_mono1(uint8_t *target,
        int32_t target_stride, int32_t target_width, int32_t target_height,
        const uint8_t *source, int32_t source_stride, int32_t source_width,
        int32_t source_height, int32_t source_format, int32_t destination_x,
        int32_t destination_y, int32_t destination_width, int32_t destination_height,
        int32_t clip_x, int32_t clip_y, int32_t clip_width,
        int32_t clip_height, uint32_t tint, int32_t opacity,
        int32_t draw_flags) {
    const int32_t source_bytes_per_pixel = source_format ==
        BMX_DISPLAY_PIXEL_FORMAT_RGB565 ? 2 : 3;
    if (!target || !source || target_stride <= 0 || target_width <= 0 ||
            target_height <= 0 || source_stride <= 0 || source_width <= 0 ||
            source_height <= 0 || destination_width <= 0 ||
            destination_height <= 0 || clip_width <= 0 || clip_height <= 0 ||
            (source_format != BMX_DISPLAY_PIXEL_FORMAT_RGB565 &&
                source_format != BMX_DISPLAY_PIXEL_FORMAT_RGB888) ||
            target_stride < (target_width + 7) / 8 ||
            source_stride < source_width * source_bytes_per_pixel ||
            opacity <= 0 || opacity > 255 || clip_x < 0 || clip_y < 0 ||
            clip_x + clip_width > target_width ||
            clip_y + clip_height > target_height || clip_x < destination_x ||
            clip_y < destination_y ||
            clip_x + clip_width > destination_x + destination_width ||
            clip_y + clip_height > destination_y + destination_height) return 0;

    draw_flags &= BMX_EMBEDDED_IMAGE_FLIP_X | BMX_EMBEDDED_IMAGE_FLIP_Y;
    for (int32_t y = clip_y; y < clip_y + clip_height; ++y) {
        int32_t source_y = (int32_t)(((int64_t)(y - destination_y) *
            source_height) / destination_height);
        if (draw_flags & BMX_EMBEDDED_IMAGE_FLIP_Y) {
            source_y = source_height - 1 - source_y;
        }
        const uint8_t *source_row = source +
            (size_t)source_y * (size_t)source_stride;
        uint8_t *target_row = target + (size_t)y * (size_t)target_stride;
        for (int32_t x = clip_x; x < clip_x + clip_width; ++x) {
            int32_t source_x = (int32_t)(((int64_t)(x - destination_x) *
                source_width) / destination_width);
            if (draw_flags & BMX_EMBEDDED_IMAGE_FLIP_X) {
                source_x = source_width - 1 - source_x;
            }
            uint32_t red;
            uint32_t green;
            uint32_t blue;
            if (source_format == BMX_DISPLAY_PIXEL_FORMAT_RGB565) {
                const uint8_t *pixel = source_row + (size_t)source_x * 2U;
                const uint32_t rgb565 = (uint32_t)pixel[0] |
                    ((uint32_t)pixel[1] << 8);
                red = (rgb565 >> 11) & 0x1fU;
                green = (rgb565 >> 5) & 0x3fU;
                blue = rgb565 & 0x1fU;
                red = (red << 3) | (red >> 2);
                green = (green << 2) | (green >> 4);
                blue = (blue << 3) | (blue >> 2);
            } else {
                const uint8_t *pixel = source_row + (size_t)source_x * 3U;
                red = pixel[0];
                green = pixel[1];
                blue = pixel[2];
            }
            if (tint != 0xffffffU) {
                red = (red * ((tint >> 16) & 0xffU) + 127U) / 255U;
                green = (green * ((tint >> 8) & 0xffU) + 127U) / 255U;
                blue = (blue * (tint & 0xffU) + 127U) / 255U;
            }

            uint8_t *target_pixel = target_row + (x >> 3);
            const uint8_t mask = (uint8_t)(0x80U >> (x & 7));
            if (opacity < 255) {
                const uint32_t destination = (*target_pixel & mask) != 0;
                red = (red * (uint32_t)opacity +
                    destination * (uint32_t)(255 - opacity) + 127U) / 255U;
                green = (green * (uint32_t)opacity +
                    destination * (uint32_t)(255 - opacity) + 127U) / 255U;
                blue = (blue * (uint32_t)opacity +
                    destination * (uint32_t)(255 - opacity) + 127U) / 255U;
            }
            if ((red | green | blue) != 0) *target_pixel |= mask;
            else *target_pixel &= (uint8_t)~mask;
        }
    }
    return 1;
}

int32_t bmx_embedded_display_blit_masked_rgb565(uint8_t *target,
        int32_t target_stride, int32_t target_width, int32_t target_height,
        const uint8_t *source, int32_t source_stride, int32_t source_width,
        int32_t source_height, const uint8_t *mask, int32_t mask_stride,
        int32_t mask_x, int32_t destination_x, int32_t destination_y,
        int32_t clip_x, int32_t clip_y, int32_t clip_width,
        int32_t clip_height, uint32_t tint, int32_t opacity,
        int32_t draw_flags) {
    if (!target || !source || !mask || target_stride < target_width * 2 ||
            target_width <= 0 || target_height <= 0 || source_stride < source_width * 2 ||
            source_width <= 0 || source_height <= 0 || mask_stride <= 0 || mask_x < 0 ||
            mask_stride < (mask_x + source_width + 7) / 8 || clip_width <= 0 ||
            clip_height <= 0 || opacity <= 0 || opacity > 255 || clip_x < 0 || clip_y < 0 ||
            clip_x + clip_width > target_width || clip_y + clip_height > target_height ||
            clip_x < destination_x || clip_y < destination_y ||
            clip_x + clip_width > destination_x + source_width ||
            clip_y + clip_height > destination_y + source_height) return 0;

    draw_flags &= BMX_EMBEDDED_IMAGE_FLIP_X | BMX_EMBEDDED_IMAGE_FLIP_Y;
    for (int32_t y = clip_y; y < clip_y + clip_height; ++y) {
        int32_t source_y = y - destination_y;
        if (draw_flags & BMX_EMBEDDED_IMAGE_FLIP_Y) {
            source_y = source_height - 1 - source_y;
        }
        const uint8_t *source_row = source + (size_t)source_y * (size_t)source_stride;
        const uint8_t *mask_row = mask + (size_t)source_y * (size_t)mask_stride;
        uint8_t *target_pixel = target + (size_t)y * (size_t)target_stride +
            (size_t)clip_x * 2U;
        for (int32_t x = clip_x; x < clip_x + clip_width; ++x) {
            int32_t source_x = x - destination_x;
            if (draw_flags & BMX_EMBEDDED_IMAGE_FLIP_X) {
                source_x = source_width - 1 - source_x;
            }
            const int32_t mask_bit = mask_x + source_x;
            if (mask_row[mask_bit >> 3] & (uint8_t)(0x80U >> (mask_bit & 7))) {
                const uint8_t *source_pixel = source_row + (size_t)source_x * 2U;
                if (tint == 0xFFFFFFU && opacity == 255) {
                    target_pixel[0] = source_pixel[0];
                    target_pixel[1] = source_pixel[1];
                } else {
                    const uint32_t source565 = (uint32_t)source_pixel[0] |
                        ((uint32_t)source_pixel[1] << 8);
                    uint32_t red = (source565 >> 11) & 0x1FU;
                    uint32_t green = (source565 >> 5) & 0x3FU;
                    uint32_t blue = source565 & 0x1FU;
                    red = (red << 3) | (red >> 2);
                    green = (green << 2) | (green >> 4);
                    blue = (blue << 3) | (blue >> 2);
                    if (tint != 0xFFFFFFU) {
                        red = (red * ((tint >> 16) & 0xFFU) + 127U) / 255U;
                        green = (green * ((tint >> 8) & 0xFFU) + 127U) / 255U;
                        blue = (blue * (tint & 0xFFU) + 127U) / 255U;
                    }
                    if (opacity < 255) {
                        const uint32_t target565 = (uint32_t)target_pixel[0] |
                            ((uint32_t)target_pixel[1] << 8);
                        uint32_t target_red = (target565 >> 11) & 0x1FU;
                        uint32_t target_green = (target565 >> 5) & 0x3FU;
                        uint32_t target_blue = target565 & 0x1FU;
                        target_red = (target_red << 3) | (target_red >> 2);
                        target_green = (target_green << 2) | (target_green >> 4);
                        target_blue = (target_blue << 3) | (target_blue >> 2);
                        red = (red * (uint32_t)opacity +
                            target_red * (uint32_t)(255 - opacity) + 127U) / 255U;
                        green = (green * (uint32_t)opacity +
                            target_green * (uint32_t)(255 - opacity) + 127U) / 255U;
                        blue = (blue * (uint32_t)opacity +
                            target_blue * (uint32_t)(255 - opacity) + 127U) / 255U;
                    }
                    const uint32_t output565 = ((red >> 3) << 11) |
                        ((green >> 2) << 5) | (blue >> 3);
                    target_pixel[0] = (uint8_t)output565;
                    target_pixel[1] = (uint8_t)(output565 >> 8);
                }
            }
            target_pixel += 2;
        }
    }
    return 1;
}

int32_t bmx_embedded_display_blit_rgb565(uint8_t *target,
        int32_t target_stride, int32_t target_width, int32_t target_height,
        const uint8_t *source, int32_t source_stride, int32_t source_width,
        int32_t source_height, int32_t source_format, int32_t destination_x,
        int32_t destination_y, int32_t destination_width, int32_t destination_height,
        int32_t clip_x, int32_t clip_y, int32_t clip_width,
        int32_t clip_height, uint32_t tint, int32_t opacity,
        int32_t draw_flags) {
    const int32_t source_bytes_per_pixel = source_format ==
        BMX_DISPLAY_PIXEL_FORMAT_RGB565 ? 2 : 3;
    if (!target || !source || target_stride <= 0 || target_width <= 0 ||
            target_height <= 0 || source_stride <= 0 || source_width <= 0 ||
            source_height <= 0 || destination_width <= 0 ||
            destination_height <= 0 || clip_width <= 0 || clip_height <= 0 ||
            (source_format != BMX_DISPLAY_PIXEL_FORMAT_RGB565 &&
                source_format != BMX_DISPLAY_PIXEL_FORMAT_RGB888) ||
            target_stride < target_width * 2 ||
            source_stride < source_width * source_bytes_per_pixel ||
            opacity <= 0 || opacity > 255 ||
            clip_x < 0 || clip_y < 0 || clip_x + clip_width > target_width ||
            clip_y + clip_height > target_height || clip_x < destination_x ||
            clip_y < destination_y ||
            clip_x + clip_width > destination_x + destination_width ||
            clip_y + clip_height > destination_y + destination_height) return 0;

    draw_flags &= BMX_EMBEDDED_IMAGE_FLIP_X | BMX_EMBEDDED_IMAGE_FLIP_Y;
    if (bmx_embedded_display_blit_rgb565_accelerator &&
            bmx_embedded_display_blit_rgb565_accelerator(target,
                target_stride, target_width, target_height, source,
                source_stride, source_width, source_height, source_format,
                destination_x, destination_y, destination_width, destination_height,
                clip_x, clip_y, clip_width, clip_height, tint, opacity,
                draw_flags)) return 1;

    if (source_format == BMX_DISPLAY_PIXEL_FORMAT_RGB565 && tint == 0xFFFFFFU &&
            opacity == 255 && destination_width == source_width &&
            destination_height == source_height && draw_flags == 0) {
        const int32_t source_x = clip_x - destination_x;
        const int32_t source_y = clip_y - destination_y;
        const size_t row_bytes = (size_t)clip_width * 2U;
        uint8_t *out = target + (size_t)clip_y * (size_t)target_stride +
            (size_t)clip_x * 2U;
        const uint8_t *in = source + (size_t)source_y * (size_t)source_stride +
            (size_t)source_x * 2U;
        for (int32_t row = 0; row < clip_height; ++row) {
            memcpy(out, in, row_bytes);
            out += target_stride;
            in += source_stride;
        }
        return 1;
    }

    for (int32_t y = clip_y; y < clip_y + clip_height; ++y) {
        int32_t source_y = (int32_t)(((int64_t)(y - destination_y) *
            source_height) / destination_height);
        if (draw_flags & BMX_EMBEDDED_IMAGE_FLIP_Y) {
            source_y = source_height - 1 - source_y;
        }
        uint8_t *out = target + (size_t)y * (size_t)target_stride +
            (size_t)clip_x * 2U;
        const uint8_t *in = source +
            (size_t)source_y * (size_t)source_stride;
        for (int32_t x = clip_x; x < clip_x + clip_width; ++x) {
            int32_t source_x = (int32_t)(((int64_t)(x - destination_x) *
                source_width) / destination_width);
            if (draw_flags & BMX_EMBEDDED_IMAGE_FLIP_X) {
                source_x = source_width - 1 - source_x;
            }
            uint32_t red;
            uint32_t green;
            uint32_t blue;
            if (source_format == BMX_DISPLAY_PIXEL_FORMAT_RGB565) {
                const uint8_t *pixel = in + (size_t)source_x * 2U;
                const uint32_t rgb565 = (uint32_t)pixel[0] |
                    ((uint32_t)pixel[1] << 8);
                red = (rgb565 >> 11) & 0x1FU;
                green = (rgb565 >> 5) & 0x3FU;
                blue = rgb565 & 0x1FU;
                red = (red << 3) | (red >> 2);
                green = (green << 2) | (green >> 4);
                blue = (blue << 3) | (blue >> 2);
            } else {
                const uint8_t *pixel = in + (size_t)source_x * 3U;
                red = pixel[0];
                green = pixel[1];
                blue = pixel[2];
            }
            if (tint != 0xFFFFFFU) {
                red = (red * ((tint >> 16) & 0xFFU) + 127U) / 255U;
                green = (green * ((tint >> 8) & 0xFFU) + 127U) / 255U;
                blue = (blue * (tint & 0xFFU) + 127U) / 255U;
            }
            if (opacity < 255) {
                const uint32_t target565 = (uint32_t)out[0] |
                    ((uint32_t)out[1] << 8);
                uint32_t target_red = (target565 >> 11) & 0x1FU;
                uint32_t target_green = (target565 >> 5) & 0x3FU;
                uint32_t target_blue = target565 & 0x1FU;
                target_red = (target_red << 3) | (target_red >> 2);
                target_green = (target_green << 2) | (target_green >> 4);
                target_blue = (target_blue << 3) | (target_blue >> 2);
                red = (red * (uint32_t)opacity +
                    target_red * (uint32_t)(255 - opacity) + 127U) / 255U;
                green = (green * (uint32_t)opacity +
                    target_green * (uint32_t)(255 - opacity) + 127U) / 255U;
                blue = (blue * (uint32_t)opacity +
                    target_blue * (uint32_t)(255 - opacity) + 127U) / 255U;
            }
            const uint32_t rgb565 = ((red >> 3) << 11) |
                ((green >> 2) << 5) | (blue >> 3);
            out[0] = (uint8_t)rgb565;
            out[1] = (uint8_t)(rgb565 >> 8);
            out += 2;
        }
    }
    return 1;
}
