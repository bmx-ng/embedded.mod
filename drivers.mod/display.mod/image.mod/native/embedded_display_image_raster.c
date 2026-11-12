/* Copyright (c) 2026 Bruce A Henderson and contributors
 * SPDX-License-Identifier: Zlib
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define BMX_EMBEDDED_IMAGE_FLIP_X 1
#define BMX_EMBEDDED_IMAGE_FLIP_Y 2

typedef int32_t (*bmx_embedded_display_blit_rgb565_accelerator_t)(
    uint8_t *target, int32_t target_stride, int32_t target_width,
    int32_t target_height, const uint8_t *source, int32_t source_stride,
    int32_t source_width, int32_t source_height, int32_t destination_x,
    int32_t destination_y, int32_t destination_width,
    int32_t destination_height, int32_t clip_x, int32_t clip_y,
    int32_t clip_width, int32_t clip_height, int32_t draw_flags);

static bmx_embedded_display_blit_rgb565_accelerator_t
    bmx_embedded_display_blit_rgb565_accelerator;

void bmx_embedded_display_set_blit_rgb565_accelerator(
        bmx_embedded_display_blit_rgb565_accelerator_t accelerator) {
    bmx_embedded_display_blit_rgb565_accelerator = accelerator;
}

int32_t bmx_embedded_display_blit_rgb565(uint8_t *target,
        int32_t target_stride, int32_t target_width, int32_t target_height,
        const uint8_t *source, int32_t source_stride, int32_t source_width,
        int32_t source_height, int32_t destination_x, int32_t destination_y,
        int32_t destination_width, int32_t destination_height,
        int32_t clip_x, int32_t clip_y, int32_t clip_width,
        int32_t clip_height, int32_t draw_flags) {
    if (!target || !source || target_stride <= 0 || target_width <= 0 ||
            target_height <= 0 || source_stride <= 0 || source_width <= 0 ||
            source_height <= 0 || destination_width <= 0 ||
            destination_height <= 0 || clip_width <= 0 || clip_height <= 0 ||
            clip_x < 0 || clip_y < 0 || clip_x + clip_width > target_width ||
            clip_y + clip_height > target_height) return 0;

    draw_flags &= BMX_EMBEDDED_IMAGE_FLIP_X | BMX_EMBEDDED_IMAGE_FLIP_Y;
    if (bmx_embedded_display_blit_rgb565_accelerator &&
            bmx_embedded_display_blit_rgb565_accelerator(target,
                target_stride, target_width, target_height, source,
                source_stride, source_width, source_height, destination_x,
                destination_y, destination_width, destination_height, clip_x,
                clip_y, clip_width, clip_height, draw_flags)) return 1;

    if (destination_width == source_width &&
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
        uint16_t *out = (uint16_t *)(target + (size_t)y *
            (size_t)target_stride) + clip_x;
        const uint16_t *in = (const uint16_t *)(source +
            (size_t)source_y * (size_t)source_stride);
        for (int32_t x = clip_x; x < clip_x + clip_width; ++x) {
            int32_t source_x = (int32_t)(((int64_t)(x - destination_x) *
                source_width) / destination_width);
            if (draw_flags & BMX_EMBEDDED_IMAGE_FLIP_X) {
                source_x = source_width - 1 - source_x;
            }
            *out++ = in[source_x];
        }
    }
    return 1;
}
