# Stage 3 Pico 2 allocation cache trial: no-go

Measured on 2026-11-04 on the attached Pico 2 with the 64 KiB SRAM arena. The existing [allocation fixture](../gc_allocation.bmx) was built in release multicore mode with the same compiler and workload used for the Stage 2 baseline: 256 batches of 64 small Objects on one task, then 256 batches of 64 Objects on each of two tasks. The parallel wall time excludes worker startup and collection. All three completed images passed the fixture's allocation, collection, checksum and heap-integrity checks.

The experimental allocator reserved ordinary heap blocks in groups of 8 or 32 for each core. Taking a reserved small Object bypassed the shared allocator metadata lock. Unused reservations were returned before each stop-the-world collection. Counts accumulated per core and were merged when both tasks stopped. The experiment was guarded by build-time settings and has **not** been retained in the runtime because it failed the throughput gate.

| Pico 2 build | One-task allocation, 16,384 Objects | Two-task wall time, 32,768 Objects | Two-task change from shared allocator | Heap high-water | Added static RAM |
| --- | ---: | ---: | ---: | ---: | ---: |
| Shared allocator | 52,909 µs | 62,515 µs | baseline | 6,240 bytes | baseline |
| 8 blocks per core | 59,824 µs | 70,264 µs | 12.4% slower | 6,240 bytes | 256 bytes |
| 32 blocks per core | 60,169 µs | 75,415 µs | 20.6% slower | 6,240 bytes | 512 bytes |

The 8-block image's parallel owner and worker allocation sums were 65,389 and 69,867 µs; the 32-block image's were 65,889 and 75,110 µs. Whole collection totals for the parallel runs were 22,227 µs (shared), 22,267 µs (8 blocks), and 22,293 µs (32 blocks). The cache did not show a collection benefit in this workload. Its per-allocation local synchronization and reservation work are plausible causes of the throughput loss, but these timings do not isolate their individual costs.

The initial cache implementation had a data race in finalizer exception cleanup: it rewrote flags on blocks while another core could claim a reserved block. ThreadSanitizer found it. The corrected experimental images passed the existing host suite under AddressSanitizer/UndefinedBehaviorSanitizer and ThreadSanitizer, including the finalizer concurrency check, before the hardware comparison. Adjacent core-local lock words also produced a severe Pico stall; separating them made the diagnostic build progress. These findings were fixes within the discarded experiment, not changes to the production runtime.

This fixture consumes cached blocks in multiples of 8 and 32, so equal high-water marks do **not** prove that memory stranding is acceptable for irregular sizes or allocation rates. Large live graphs, fragmented heaps, collection phase times, and maximum poll gaps remain unmeasured. The Stage 3 adoption gate is not met. A future allocator change needs evidence that actual lock **wait time**, not only the fraction of acquisitions with a failed spin, is a meaningful cost, followed by a throughput and memory comparison on both small and irregular workloads.
