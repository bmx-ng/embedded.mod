# Multicore Select liveness check

The [fixture](../../../tests/embedded_gc_select_temporary_device.bmx) evaluates a `Select` selector through a managed field-read temporary, then compares two managed field-read case values in order. A matching body enters a polling `While` loop. It also checks a fallback case. Expected serial output is `GC_SELECT,format=1,first=2,second=2,default=4`.

Both Pico 2 and ESP32-S3 release images built with a 64 KiB managed arena and `-gc-multicore`. The ESP32-S3 image was flashed and hash-verified on 2026-11-04; its serial monitor repeated the expected output eight times. The compiler IR regression checks that each managed temporary is cleared before the first case-body poll and that a matched first case value skips evaluation of the second value. It also verifies that the default single-core path keeps direct comparisons. The host GC sanitizer suite passed.

The Pico 2 image built, but the previous one-shot probe exited before USB serial could enumerate. The persistent fixture awaits a physical BOOTSEL reconnect before flashing and observing serial output.
