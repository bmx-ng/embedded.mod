/* Copyright (c) 2026 Bruce A Henderson and contributors
 * SPDX-License-Identifier: Zlib
 */

#include <math.h>

#define BMX_GRAPHICS2D_DEGREES_TO_RADIANS 0.01745329251994329576923690768489

double bmx_graphics2d_sin(double degrees) {
    return sin(degrees * BMX_GRAPHICS2D_DEGREES_TO_RADIANS);
}

double bmx_graphics2d_cos(double degrees) {
    return cos(degrees * BMX_GRAPHICS2D_DEGREES_TO_RADIANS);
}
