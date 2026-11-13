/* Copyright (c) 2026 Bruce A Henderson and contributors
 * SPDX-License-Identifier: Zlib
 */
#include "ui_math.h"
#include <math.h>

#define BMX_UI_DEGREES_TO_RADIANS 0.01745329251994329576923690768489

double bmx_ui_sin(double degrees) {
	return sin(degrees * BMX_UI_DEGREES_TO_RADIANS);
}

double bmx_ui_cos(double degrees) {
	return cos(degrees * BMX_UI_DEGREES_TO_RADIANS);
}
