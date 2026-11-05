# Stage 2 allocation throughput and allocator contention

Measured on 2026-11-04 in release builds on the attached Pico 2 (RP2350 ARM) and ESP32-S3 (`esp32s3_n8r8`). The [allocation fixture](../gc_allocation.bmx) creates 64 small Objects per batch for 256 batches: 16,384 allocations per task. It times each allocation batch and performs an explicit collection outside the allocation interval. The parallel case starts one managed worker before timing, releases both tasks for each batch, waits for both to finish, then collects. Its `wall_us` includes batch handoff and waiting, but excludes worker start/join and collections. The fixture checks the Object allocation and collection counts, no automatic collections or allocation failures, checksums and heap integrity.

The ordinary single-core build is the default. Multicore was built with `-gc-multicore`. Captured benchmark records are [Pico 2](multicore_stage2_allocation_pico2.log) and [ESP32-S3](multicore_stage2_allocation_esp32s3.log).

| Board and arena | Single-core, 16,384 Objects | Multicore owner only, 16,384 Objects | Multicore two tasks, 32,768 Objects | Two-task throughput vs two sequential multicore batches |
| --- | ---: | ---: | ---: | ---: |
| Pico 2, 64 KiB | 36,270 µs | 53,021 µs | 62,883 µs | 1.69× |
| Pico 2, 256 KiB | 36,272 µs | 53,038 µs | 62,067 µs | 1.71× |
| ESP32-S3, 64 KiB | 88,268 µs | 267,398 µs | 316,469 µs | 1.69× |
| ESP32-S3, 256 KiB | 88,261 µs | 267,414 µs | 316,510 µs | 1.69× |

The one-task opt-in cost is about 1.46× on Pico 2 and 3.03× on S3 in this fixture. The standard single-core benchmark remains unchanged after Stage 2, as recorded in [the matched baseline](multicore_stage2_singlecore_performance.md). A two-task allocation batch is faster than two sequential batches in opt-in mode, but on S3 its 316 ms is still much longer than two 88 ms batches in default single-core mode. These timings describe this Object shape and generated code, not all applications.

The timed collections after each batch total about 11.6 ms (Pico) or 17.3 ms (S3) across 256 small owner-only batches in default mode. The corresponding opt-in totals are about 12.0 ms and 19.1 ms; with a registered worker they are about 22.0 ms and 31.6 ms. These are whole collection calls, including rendezvous when a worker exists, not phase timings or latency percentiles.

## Lock diagnostic

The runtime has compile-time diagnostic counters for allocator lock acquisitions, acquisitions that needed at least one spin, and failed spin attempts. They are absent from normal builds. Set `BMX_EMBEDDED_GC_PERF_COUNTERS=1` and use a clean `-gc-multicore` build to enable them; clean the application build again when disabling them. The Pico and ESP32 CMake targets pass the setting only to that opt-in image. Counter aggregation happens after unlocking to limit added contention. The profile still changes timing, so compare the counters, not profile durations, with the normal runs. Raw profiles: [Pico 2](multicore_stage2_allocation_profile_pico2.log), [ESP32-S3](multicore_stage2_allocation_profile_esp32s3.log).

| Board | Owner-only contended / acquisitions | Two-task contended / acquisitions | Failed spin attempts, two tasks |
| --- | ---: | ---: | ---: |
| Pico 2 | 0 / 16,384 | 13,322 / 32,768 (40.7%) | 39,822 |
| ESP32-S3 | 0 / 16,384 | 31 / 32,768 (0.09%) | 80 |

The high Pico contention warrants a Stage 3 *experiment* with per-core allocation state, provided its extra memory and fragmentation are measured. S3 has almost no observed lock waiting in this workload, so contention alone does not justify per-core regions there.

An additional [isolation fixture](../gc_allocation_isolation.bmx) compares one allocation per generated loop poll, eight allocations per poll, and a native loop that calls the same Object allocator without generated root frames or loop polls. On S3, the owner-only multicore times were 267,416, 242,630 and 87,343 µs respectively; the default native loop took 46,901 µs. Reducing polls helped, while the native loop still shows an opt-in allocator/context cost. This is an inference from different generated paths, not a pure measurement of any one instruction. Raw isolation runs: [Pico 2](multicore_stage2_allocation_isolation_pico2.log), [ESP32-S3](multicore_stage2_allocation_isolation_esp32s3.log).

The Pico isolation image differed sharply from the smaller allocation image: its default generated one-per-loop case took 174 ms, while the smaller image repeatedly took about 36 ms with the same allocation body. Its native cases were 27.5 ms default and 30.4 ms opt-in. Image layout or other build effects may explain this gap. Use the smaller matched image and lock counters for the Pico Stage 3 decision; do not attribute the isolation-image gap to polling or locks alone.

Both arena configurations reached only 3,168 bytes high-water in default mode and 6,240 bytes in opt-in mode. The 256 KiB runs verify that configuration, but do not test a heap occupied near 256 KiB. Capacity-scaled live-graph and fragmented-heap collection pauses, request-to-ack timing, trace/sweep/finalizer phase timing, and poll-gap percentiles remain to be measured before deciding whether a Stage 3 allocator prototype improves end-to-end behavior. Default single-core mode remains the performance choice for single-task S3 allocation workloads measured here.
