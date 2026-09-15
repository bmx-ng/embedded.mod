' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Portable monotonic time and sleep operations for embedded targets.
about: The monotonic clock has microsecond units and an unspecified epoch. It
continues forwards until the target restarts and is suitable for measuring
durations. Sleep operations do not return before the requested duration, but
may return later because of target scheduling and interrupts.
End Rem
Module Embedded.System.Time
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Extern "C"
	Function MonotonicMicroseconds:ULong() = "bmx_embedded_time_microseconds"
	Function MonotonicMilliseconds:ULong() = "bmx_embedded_time_milliseconds"
	Function SleepMilliseconds(milliseconds:UInt) = "bmx_embedded_sleep_milliseconds"
	Function SleepMicroseconds(microseconds:ULong) = "bmx_embedded_sleep_microseconds"
End Extern
?
