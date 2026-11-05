# Multicore exception temporary liveness check

The [fixture](../../../tests/embedded_gc_exception_temporary_device.bmx) registers the Stage 1 collector owner, then throws from a method called through a managed field-read temporary. It collects after removing the owning reference in three places: a `Catch` block, a `Finally` block, and `Using` cleanup. Each path expects the holder and child to be reclaimed, so its live-object delta is zero. The fixture also checks heap integrity and that collection actually ran.

On 2026-11-04, Pico 2 and ESP32-S3 release images built with a 64 KiB arena and `-gc-multicore`. The ESP32-S3 image was flashed and hash-verified; the Pico 2 image was flashed and verified. Both serial monitors repeatedly reported `slot=0,catch=0,finally=0,using=0,valid=1,before=1,after=2,failures=0,reclaimed=2`. An earlier probe without owner registration correctly refused all collections; the fixture now registers the owner before testing.

The compiler IR regression checks that generated cleanup follows `bmx_embedded_exception_catch()` and precedes a `Catch` or `Finally` poll. The host collector sanitizer suite passes.
