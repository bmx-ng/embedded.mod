# Single-core firmware build baselines

Captured 2026-11-03 for `tests/embedded_gc_sweep_conformance.bmx`, release mode, 64 KiB managed arena. These images use the existing single-core runtime in the separate target distributions. Rebuild after each multicore stage with the same board, heap, toolchain, and application before comparing size.

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

The second command runs only from `BlitzMax-esp32`; the first runs only from `BlitzMax-pico`. Flash/RAM use reported by the builders depends on the board and linker script.

The attached Pico 2 (RP2350 ARM) passed the [on-device sweep conformance test](multicore_stage0_pico2_conformance.log) (`GC_CHECK,checks=pass`), then completed the [sweep timing log](multicore_stage0_pico2_sweep.log) and [standard GC benchmark log](multicore_stage0_pico2_benchmark.log). All used release, 64 KiB, single-core builds from `BlitzMax-pico`. The timing logs contain all samples and completion/check markers; `summarize.py` validated their shape and checksums.

| Pico 2 case | Median | p95 |
| --- | ---: | ---: |
| Sweep: all live | 448 µs | 466 µs |
| Sweep: contiguous free | 141 µs | 142 µs |
| Sweep: fragmented free | 179 µs | 180 µs |
| Sweep: raw survivors | 183 µs | 184 µs |
| GC: live backward chain | 168.5 µs | 173 µs |
| GC: reclaim garbage | 203 µs | 230 µs |

The standard benchmark's 120,000 ordinary update rounds took 772,005 µs with the expected checksum, providing a mutator-work baseline. Its heap high-water mark was 6,560 bytes. These are per-case benchmark durations, not maximum application pause guarantees. The sweep timing and standard benchmark use different graphs and should be compared only with their corresponding post-change runs.

The attached ESP32-S3 (USB Serial/JTAG, revision v0.2) accepted and verified the 64 KiB conformance firmware. A repeating diagnostic variant also flashed and verified. However, resetting through `/dev/cu.usbmodem101` repeatedly entered the ROM download monitor (`boot:0x0 (DOWNLOAD(USB/UART0))`), and no application `GC_CHECK` output was captured. This is a serial/boot capture limitation; it does not establish a GC pass or failure on the ESP32. On-device ESP32 conformance and timing, allocation throughput, broader fault injection, and long soaks remain open Stage 0 measurements.

The combined `BlitzMax-bcc2` checkout's current `bin/bmk` rejected an unrelated newer ESP32 board profile field (`resource.ethernet.mdc`) before configuring a Pico build. Its `bmk_src` source recognizes that field, so the combined checkout's bmk binary appears stale. Refresh that tool before using the combined checkout for multicore integration builds. The target-distribution baseline builds above completed without modifying tracked files.
