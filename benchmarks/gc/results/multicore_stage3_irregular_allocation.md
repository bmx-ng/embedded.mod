# Stage 3 mixed-size and uneven-rate allocation

Measured on 2026-11-04 on the attached Pico 2 and ESP32-S3 (`esp32s3_n8r8`) with 64 KiB SRAM arenas and release `-gc-multicore` builds. The [fixture](../gc_allocation_irregular.bmx) allocates Objects of 16, 48, 112 and 240 bytes, selecting sizes from a deterministic pseudorandom sequence. Each case runs 256 batches. A batch releases both tasks, times their native allocation loops and the parallel wall interval, waits for both, then explicitly collects outside the allocation interval. The three cases allocate 64/64, 64/16 and 16/64 Objects per owner/worker batch. Each image passed 768 collections, 73,728 Object allocations, checksums and heap-integrity checks without an automatic collection or arena failure.

| Board and image | Owner/worker per batch | Parallel wall | Contended / lock entries | Failed spins | Accumulated lock wait |
| --- | ---: | ---: | ---: | ---: | ---: |
| Pico 2, ordinary | 64/64 | 41,857 µs | — | — | — |
| Pico 2, counters | 64/64 | 44,945 µs | 4,703 / 32,768 (14.4%) | 22,860 | — |
| Pico 2, timed counters | 64/64 | 49,650 µs | 4,910 / 32,768 (15.0%) | 23,996 | 2,979 µs |
| Pico 2, ordinary | 64/16 | 39,928 µs | — | — | — |
| Pico 2, counters | 64/16 | 42,627 µs | 1,314 / 20,480 (6.4%) | 5,982 | — |
| Pico 2, timed counters | 64/16 | 47,070 µs | 1,231 / 20,480 (6.0%) | 6,028 | 742 µs |
| Pico 2, ordinary | 16/64 | 40,896 µs | — | — | — |
| Pico 2, counters | 16/64 | 44,805 µs | 1,107 / 20,480 (5.4%) | 5,449 | — |
| Pico 2, timed counters | 16/64 | 48,817 µs | 1,116 / 20,480 (5.4%) | 5,332 | 687 µs |
| ESP32-S3, ordinary | 64/64 | 111,989 µs | — | — | — |
| ESP32-S3, counters | 64/64 | 142,759 µs | 809 / 32,768 (2.5%) | 937 | — |
| ESP32-S3, ordinary | 64/16 | 99,733 µs | — | — | — |
| ESP32-S3, counters | 64/16 | 129,561 µs | 419 / 20,480 (2.0%) | 465 | — |
| ESP32-S3, ordinary | 16/64 | 104,226 µs | — | — | — |
| ESP32-S3, counters | 16/64 | 134,059 µs | 430 / 20,480 (2.1%) | 566 | — |

These are separate firmware images; compare diagnostic counters and waits within a diagnostic image, and use ordinary images for throughput. Profiling adds visible cost, especially on ESP32-S3. Pico wait is the sum across both cores, measured with a 1 µs hardware timer only in the timed image. Individual waits are often below the timer resolution, and timing instrumentation changes scheduling. The 2,979 µs balanced wait is about 0.61 µs per contended acquisition in that image; it is not a wall-time saving that a new allocator could claim directly.

The mixed-size test reduced Pico's failed-spin fraction from about 41% in the [small-Object fixture](multicore_stage3_lock_cost_pico2.md) to about 14% with equal rates. Uneven rates reduced it to about 5–6%. ESP32-S3 remained below 3% in all three cases. No case establishes a lock cost large enough to justify the tested per-core cache, which was slower on the small-Object workload. **Stage 3 decision: keep the shared allocator; do not adopt that cache.** No faster per-core allocator has passed the throughput gate.

All allocated Objects become unreachable between batches. The benchmark varies sizes and task rates but does not model a persistent live graph, fragmented free space, Arrays or Strings. Its high-water marks were about 21–22 KiB; they include fixture bookkeeping and do not prove a per-core reservation policy would avoid memory stranding. Collection phase and maximum pause measurements remain separate work, and any future allocator proposal should be gated by a workload showing substantial measured lock cost first.
