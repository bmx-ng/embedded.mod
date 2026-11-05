# Stage 1 native handshake device checks

Run on 2026-11-03 with Pico 2 (RP2350 ARM) and ESP32-S3 (`esp32s3_n8r8`). The [device fixture](../../../tests/embedded_gc_handshake_device.bmx) launches a native worker on the second core. It checks a successful cooperative stop, a failed request while the worker deliberately does not poll, a later successful stop, and clean worker removal. It does not execute managed code on the worker or validate the target runtime adapter.

Both release builds used a 64 KiB managed heap and the fixed two-slot handshake source from this repository. The separate `BlitzMax-pico` and `BlitzMax-esp32` distributions supplied the target toolchains and existing single-core runtime. Their embedded include directories were temporarily given a link to the handshake header for these builds; the links were removed afterward. The Pico native test needs `BLITZMAX_PICO_MULTICORE_ENABLED=ON` in its CMake cache. The default is `OFF`; no multicore library is linked to ordinary single-core applications. The generated images were flashed and verified on the attached boards.

| Board | Serial evidence | Result |
| --- | --- | --- |
| Pico 2 | [captured output](multicore_stage1_pico2_handshake.log) | Pass |
| ESP32-S3 | [captured output](multicore_stage1_esp32s3_handshake.log) | Pass |

The ESP32 application was started from the flasher with a watchdog reset. This avoided the USB control-line reset behavior observed during Stage 0.

An unchanged Pico single-core GC conformance application was rebuilt with the opt-in CMake logic disabled and with that logic absent, using the same output name and build settings. Both ELF and UF2 hashes matched exactly; ELF sections were 51,976 bytes text, 0 data, and 69,088 BSS. The earlier unconditional SDK library link grew this same application to 52,004 bytes text and 71,144 BSS. That measurement is why the library is opt-in.
