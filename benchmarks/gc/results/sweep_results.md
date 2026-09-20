# Linear sweep and all-live exit — 2026-09-20

Baseline: merged embedded runtime `4f0c31f47d880eabba7e1d555b073f87f914c7cf`.
Candidate: the same runtime with an all-live early return and linear free-list
rebuilding during sweep. The mark queue and two-cursor lookup are unchanged.
No runtime switch, additional allocation header fields, or side table is added.

## Measurements

Release builds on the attached Pico 2 W and ESP32-S3 44-pin N16R8. All heaps
are in SRAM. These are single-context managed runtimes, even though both chips
have two cores; they do not measure multicore managed execution.

Values are median collection times in microseconds, over 12 samples per case.
Before and after use the same `gc_sweep.bmx` and `gc_sweep.c`. Setup, root
registration, validation, manual frees, and allocation reuse are outside the
timed interval. No samples are discarded. Raw logs include all samples and
can be checked with `summarize.py` for median and p95.

| Board / heap / nodes | Case | Before (µs) | After (µs) | Reduction |
| --- | --- | ---: | ---: | ---: |
| Pico / 64 KiB / 256 | Fully live chain | 490 | 448 | 8.6% |
| Pico / 64 KiB / 256 | Contiguous garbage | 199.5 | 141 | 29.3% |
| Pico / 64 KiB / 256 | Fragmented garbage | 1,778 | 178 | 90.0% |
| Pico / 64 KiB / 256 | Raw survivors | 983 | 182 | 81.5% |
| Pico / 256 KiB / 1,024 | Fully live chain | 1,903 | 1,722 | 9.5% |
| Pico / 256 KiB / 1,024 | Contiguous garbage | 748 | 510 | 31.8% |
| Pico / 256 KiB / 1,024 | Fragmented garbage | 25,409 | 660 | 97.4% |
| Pico / 256 KiB / 1,024 | Raw survivors | 13,056 | 677 | 94.8% |
| ESP32-S3 / 256 KiB / 1,024 | Fully live chain | 2,193 | 1,942 | 11.4% |
| ESP32-S3 / 256 KiB / 1,024 | Contiguous garbage | 1,021 | 657 | 35.7% |
| ESP32-S3 / 256 KiB / 1,024 | Fragmented garbage | 30,858 | 894 | 97.1% |
| ESP32-S3 / 256 KiB / 1,024 | Raw survivors | 15,904 | 906.5 | 94.3% |

The fragmented case intentionally exposes the old repeated free-list search:
managed objects alternate with raw 16-byte allocations, then all raw gaps
are freed in allocation order. The raw-survivor case frees only alternate
gaps and verifies the remaining raw payloads after collection. The other
cases use a live forward chain or unrooted contiguous objects. Counts scale
with heap capacity; this is not a measurement of completely full heaps.
The helper's fixed raw-pointer array belongs only to the benchmark firmware.

On Pico, quadrupling the object count increases fragmented collection time
about 14.3× before and 3.7× after. This supports the expected removal of the
quadratic free-list work. The 34–38× speedups at 256 KiB are stress-case
results, not a prediction for every application.

Raw captures:

- [Pico 64 KiB before](gcsweep_pico_before64.log) / [after](gcsweep_pico_after64.log)
- [Pico 256 KiB before](gcsweep_pico_before256.log) / [after](gcsweep_pico_after256.log)
- [ESP32-S3 256 KiB before](gcsweep_esp_before256.log) / [after](gcsweep_esp_after256.log)

## Correctness and broader workloads

Every sweep benchmark sample passed checks for reclaimed object count, live
chain values, raw payload preservation, absence of unexpected automatic
collections, heap integrity, and allocation reuse after coalescing.

Both boards also passed `gc_varied.bmx`: shared references, arrays, dynamic
strings, cycles, mixed reclamation, and an anchored live graph under allocation
pressure. Checksum remains 3154, with 15 automatic collections and the same
65,520-byte arena high-water mark.

| Varied case, 64 KiB | Pico before (µs) | Pico after (µs) | ESP32-S3 before (µs) | ESP32-S3 after (µs) |
| --- | ---: | ---: | ---: | ---: |
| Empty | 17 | 16 | 26 | 24 |
| Forward chain | 174 | 160 | 219 | 201 |
| Wide shared graph | 185 | 164 | 222 | 196.5 |
| Mixed cycle | 90 | 78 | 110 | 96 |
| Mixed reclamation | 152 | 106 | 205 | 137 |

These broader comparisons use the previously recorded merged lookup runs
([Pico](two_cursor_pico2w_varied.log), [ESP32-S3](two_cursor_s3_varied.log))
and the new sweep runs ([Pico](gcvaried_sweep_pico.log),
[ESP32-S3](gcvaried_sweep_esp.log)), rather than fresh paired baselines.
Small cases show timing variability: for example, Pico mixed-cycle p95 was
119 µs before and 125 µs after despite the improved median. These samples
support lower typical times, not a claim that every collection is faster.

The new native [regression test](../../../tests/embedded_gc_sweep_conformance.c)
passed on [Pico 2 W](gcsweep_checks_pico.log) and
[ESP32-S3](gcsweep_checks_esp.log). It checks finalizer resurrection,
child survival during a finalizer cycle, at-most-once finalization, recovery
from an escaping finalizer exception, reset collection statistics, and
interleaved live managed objects, garbage, and manual allocations.

## Behaviour and limits

The early return runs only after a successful reachability audit reports no
unreachable objects, arrays, or strings. Collection statistics are still reset.
Finalizer discovery and invocation are unchanged; a finalizer cycle still does
not sweep. A subsequent collection observes resurrection before reclaiming.

Sweep rebuilds the free list in reverse physical order and joins adjacent free
or newly dead blocks as it walks. Allocation placement can therefore differ
from the old free-list ordering. Manual freeing and ordinary allocation retain
their existing code paths; application-level allocation throughput was not
measured in this experiment. The collector remains stop-the-world.
