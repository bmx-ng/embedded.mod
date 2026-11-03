# Single-core firmware build baselines

Captured 2026-11-03 for `tests/embedded_gc_sweep_conformance.bmx`, release mode, 64 KiB managed arena. These images use the existing single-core runtime in the separate target distributions; they are **build-size** baselines, not on-device timing results. No board was connected. Rebuild after each multicore stage with the same board, heap, toolchain, and application before comparing size.

| Target | Source revisions (`embedded.mod`, target module, compiler module) | Firmware/application image | ELF `size` text / data / bss |
| --- | --- | ---: | ---: |
| Pico 2, RP2350 ARM (`BlitzMax-pico`, Pico SDK 2.3.0) | `505ba42`, `21ffcb7`, `a26fea7` | UF2: 94 KiB | 51,960 / 0 / 69,088 bytes |
| ESP32-S3 `esp32s3_n8r8` (`BlitzMax-esp32`, ESP-IDF 6.1.0) | `b409cbb`, `b9efe45`, `a26fea7` | application BIN: 186 KiB | 138,977 / 51,044 / 369,505 bytes |

The ESP32 ELF totals include ESP-IDF components and memory regions beyond the managed runtime. The binary image and ELF sections answer different questions; compare each column only against the same target/build setup. The 64 KiB managed arena is included in BSS for Pico and allocated at runtime on ESP32. The host-side opt-in validator and test injection hook are not enabled in these images.

Reproduction from the corresponding target distribution root:

```sh
./bin/bmk makeapp -a -r -l pico -g arm -board pico2 -heap 64k -o /private/tmp/multicore_stage0_pico_gc mod/embedded.mod/tests/embedded_gc_sweep_conformance.bmx
./bin/bmk makeapp -a -r -l esp32 -g xtensa -board esp32s3_n8r8 -heap 64k -o /private/tmp/multicore_stage0_esp32_gc mod/embedded.mod/tests/embedded_gc_sweep_conformance.bmx
```

The second command runs only from `BlitzMax-esp32`; the first runs only from `BlitzMax-pico`. Flash/RAM use reported by the builders depends on the board and linker script. Hardware latency, allocation throughput, pause duration and soak results remain open Stage 0 measurements.

The combined `BlitzMax-bcc2` checkout's current `bin/bmk` rejected an unrelated newer ESP32 board profile field (`resource.ethernet.mdc`) before configuring a Pico build. Its `bmk_src` source recognizes that field, so the combined checkout's bmk binary appears stale. Refresh that tool before using the combined checkout for multicore integration builds. The target-distribution baseline builds above completed without modifying tracked files.
