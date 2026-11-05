# Single-core performance after Stage 2

On 2026-11-04, the unchanged [standard GC benchmark](../gc_benchmark.bmx) was rebuilt in release, single-core mode with the current compiler and runtime, a 64 KiB arena and the attached Pico 2 and ESP32-S3. The images were flashed and verified, and their full [Pico](multicore_stage2_singlecore_pico2_benchmark.log) and [S3](multicore_stage2_singlecore_esp32s3_benchmark.log) serial logs were validated with `summarize.py`. The checksum and 6,560-byte arena high-water mark matched the [Stage 0 baseline](multicore_stage0_build_baselines.md).

| Workload | Pico 2, Stage 0 → current | ESP32-S3, Stage 0 → current |
| --- | ---: | ---: |
| 120,000 ordinary update rounds | 772,005 → 772,006 µs | 2,744,619 → 2,744,623 µs |
| GC, live backward chain median | 168.5 → 170 µs | 199 → 199 µs |
| GC, reclaim garbage median | 203 → 204 µs | 249 → 249 µs |

The differences are within the run-to-run noise of these short device measurements. The ordinary single-core configuration remains the default. The opt-in multicore collector and its synchronization are compiled only when requested. The Pico deferred-event queue's single-core runtime disassembly also matched its pre-lock version instruction for instruction.

The S3 takes about 3.56 times as long as Pico 2 on the ordinary update workload, 4.74 times as long on the [million-job start/join soak](multicore_stage2_soak_hardware.md), and 2.33 times as long on the [persistent-worker stress fixture](multicore_stage2_stress_hardware.md). The matched GC medians differ much less: about 1.17 times for the live backward chain and 1.22 times for garbage reclamation in the current single-core images. These ratios describe these fixed workloads and boards; they do not isolate CPU instruction throughput.
