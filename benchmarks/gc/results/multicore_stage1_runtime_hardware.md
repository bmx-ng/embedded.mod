# Stage 1 runtime adapter device checks

Run on 2026-11-03 with an attached Pico 2 (RP2350 ARM) and ESP32-S3 (`esp32s3_n8r8`). The [fixture](../../../tests/embedded_gc_runtime_device.bmx) uses the actual embedded runtime, its two execution contexts, and the target task bindings. One native worker registers, holds the only precise root to an object, and polls while the owner collects. The owner verifies that an additional unrooted object is swept while the rooted object survives, then verifies reclamation after the worker clears its root. The worker next stops polling; the owner verifies that the timed-out collection does not sweep, then that collection succeeds after polling resumes. Both paths check heap integrity.

The release builds used 64 KiB managed arenas and the opt-in target CMake settings: `BLITZMAX_PICO_MULTICORE_ENABLED=ON` with `BLITZMAX_PICO_GC_MULTICORE=ON`, or `BLITZMAX_ESP32_GC_MULTICORE=ON`. At the time of this test, bmk did not pass those settings, so its generated target build was reconfigured with CMake before linking. bmk has since gained `-gc-multicore`. Both images were flashed, verified, and observed over serial. The ESP32 image was started with esptool's watchdog reset.

| Board | Serial evidence | Result |
| --- | --- | --- |
| Pico 2 | [captured output](multicore_stage1_runtime_pico2.log) | Pass |
| ESP32-S3 | [captured output](multicore_stage1_runtime_esp32s3.log) | Pass |

The first ESP32 image failed at startup because the owner task's context index was unknown before arena binding. The task-index adapter now recognizes the unbound CPU-0 startup context; the rebuilt image passed the same checks. This test uses a native root-only worker. It does not validate generated managed code on the worker, shared allocation, arbitrary native callbacks, or general multicore GC correctness.
