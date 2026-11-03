# Stage 1 native handshake device checks

Run on 2026-11-03 with Pico 2 (RP2350 ARM) and ESP32-S3 (`esp32s3_n8r8`). The [device fixture](../../../tests/embedded_gc_handshake_device.bmx) launches a native worker on the second core. It checks a successful cooperative stop, a failed request while the worker deliberately does not poll, a later successful stop, and clean worker removal. It does not execute managed code on the worker or validate the target runtime adapter.

Both release builds used a 64 KiB managed heap and the fixed two-slot handshake source from this repository. The separate `BlitzMax-pico` and `BlitzMax-esp32` distributions supplied the target toolchains and existing single-core runtime. Their embedded include directories were temporarily given a link to the handshake header for these builds; the links were removed afterward. The Pico build additionally linked `pico_multicore`; that target dependency is now recorded in the Pico module source. The generated images were flashed and verified on the attached boards.

| Board | Serial evidence | Result |
| --- | --- | --- |
| Pico 2 | [captured output](multicore_stage1_pico2_handshake.log) | Pass |
| ESP32-S3 | [captured output](multicore_stage1_esp32s3_handshake.log) | Pass |

The ESP32 application was started from the flasher with a watchdog reset. This avoided the USB control-line reset behavior observed during Stage 0.
