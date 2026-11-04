# Stage 1 generated managed-worker device checks

Run on 2026-11-04 with an attached Pico 2 (RP2350 ARM) and ESP32-S3 (`esp32s3_n8r8`). The [fixture](../../../tests/embedded_gc_managed_worker_device.bmx) creates an ordinary managed object on the owner context, passes it to a native worker trampoline, and runs a compiler-generated BlitzMax function on the second core/task. That function reads the object, holds it in a generated root slot, and polls in a `While` loop. The owner removes its root, allocates an unrooted object, and collects. The test checks that the unrooted object is swept while the worker-rooted object survives. After the worker clears its root, the owner collects again and checks that the object is reclaimed. Both collections check heap integrity, and the worker exits and unregisters.

Both release builds used 64 KiB managed arenas and the new `bmk makeapp -gc-multicore` path. This passed `--embedded-multicore` to bcc and the target CMake options to Pico or ESP32 automatically. The generated worker C was inspected for its parameter root slot and a poll inside each wait loop. The Pico image was uploaded and verified with picotool; the ESP32 image was flashed and hash-verified with esptool, then started by watchdog reset.

| Board | Serial evidence | Result |
| --- | --- | --- |
| Pico 2 | [captured output](multicore_stage1_managed_worker_pico2.log) | Pass |
| ESP32-S3 | [captured output](multicore_stage1_managed_worker_esp32s3.log) | Pass |

A separate default Pico build had both GC and Pico multicore CMake options `OFF` and generated no multicore C guard. The opt-in mode uses separate interface and build paths. This test covers one managed worker holding and releasing a precise root. It does not establish safe worker allocation, heap mutation, arbitrary native callbacks, exception propagation, or general multicore GC correctness.
