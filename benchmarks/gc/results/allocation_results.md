# Remove duplicate allocation search — 2026-09-20

Baseline: merged runtime `124f229` (linear collector sweep). Candidate removes
allocation's second free-list walk without changing first-fit selection,
splitting, coalescing, collection policy, or block metadata. The helper used
by manual freeing still searches when it needs to unlink an arbitrary block.

## Results

Both attached boards used release builds and 64 KiB SRAM heaps. Managed code
runs in one context; these are not multicore managed-runtime measurements.
Before and after use the same timed benchmark code and workload configuration.

All values below are median elapsed microseconds across 12 samples, with no
samples discarded. The first five rows time **batches of 32 allocation attempts**.
The last row times **2,048 allocation/free/write replacements** across 64 live
slots. These are batch times, not individual allocation latency.

| Workload | Pico before (µs) | Pico after (µs) | Reduction | ESP32-S3 before (µs) | ESP32-S3 after (µs) | Reduction |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Head matches | 21 | 19 | 9.5% | 57 | 53 | 7.0% |
| Middle matches | 225 | 116 | 48.4% | 287 | 143 | 50.2% |
| Tail matches | 430 | 212 | 50.7% | 517 | 232.5 | 55.0% |
| Split reusable blocks | 483.5 | 240 | 50.4% | 580 | 262 | 54.8% |
| Unsuccessful searches | 293.5 | 258 | 12.1% | 352 | 289 | 17.9% |
| Mixed allocation/free/write | 11,349 | 11,204 | 1.3% | 14,896 | 14,686 | 1.4% |

The substantial savings occur when a successful allocation would previously
have traversed a long free-list prefix twice. The mixed workload also includes
manual-free lookup and memory writes, which this change does not accelerate.
Its roughly 1% improvement is a better indication of the modest overall gain
in this particular workload; the 50% figures are not whole-application speedups.

Raw paired captures:

- [Pico before](allocation_pico_64k_before.log) / [after](allocation_pico_64k_after.log)
- [ESP32-S3 before](allocation_esp_64k_before.log) / [after](allocation_esp_64k_after.log)

Run `summarize.py` on these files to check complete sample sets and see p95.

## Why the loop examines two blocks

The first trial retained a pointer to the incoming free-list link. Successful
searches improved, but the added loop work slowed unsuccessful searches:

| Scan version: unsuccessful batch | Pico (µs) | ESP32-S3 (µs) |
| --- | ---: | ---: |
| Merged baseline | 293.5 | 352 |
| Incoming-link trial | 327.5 | 449.5 |
| Simple predecessor trial | 327.5 | 353 |
| Final paired scan | 258 | 289 |

The final version tests the head, then examines two successive blocks per loop
iteration. It retains the predecessor when leaving the loop, avoiding a
predecessor copy at every skipped block. A match still unlinks in constant time
and is always the first suitable block. No runtime switches select among trials.

Trial evidence:
[Pico incoming link](allocation_pico_64k_link_trial.log),
[ESP32-S3 incoming link](allocation_esp_64k_link_trial.log),
[Pico predecessor](allocation_pico_64k_predecessor_trial.log),
[ESP32-S3 predecessor](allocation_esp_64k_predecessor_trial.log).

There are no new persistent fields or per-block memory costs. On the measured
Pico build, the allocator function symbol grows from 284 to 308 bytes (+24
bytes of code/literal storage, as reported by `arm-none-eabi-nm -S`). This is
not a claim about the size of the entire firmware or the ESP32 build.

## Workloads and checks

`allocation_search.bmx` and its C helper create 128 small gaps and 32 target
allocations, with guard allocations kept live. The order in which targets and
gaps are freed places suitable blocks near the head, middle, or tail. Exact-fit
requests are 128 bytes. The split case requests 192 bytes after freeing
256-byte targets; legitimate prior coalescing is allowed in this case.

The unsuccessful-search control deliberately requests the whole arena through
the non-collecting allocation API, ensuring a failed search without timing a
collection. It is a scan control, not a model of normal application failure
frequency. The mixed workload uses a fixed random seed and varied sizes.

Every sample checks:

- Heap integrity and absence of unexpected automatic collections.
- Expected first-fit addresses in exact-fit cases.
- Reuse without arena growth in the focused batches, distinct payloads,
  non-overlap, and live guards.
- Expected failure counts in the unsuccessful-search case.
- Surviving mixed-workload payloads and heap integrity after cleanup.

A benchmark failure prints a diagnostic and leaves USB service running, so it
does not require BOOTSEL recovery merely to load a corrected test.

The existing varied managed-allocation benchmark passed on both boards:
[Pico](allocation_pico_varied.log), [ESP32-S3](allocation_esp_varied.log).
This covers shared references, cycles, objects, arrays, strings, and allocation
pressure. Both retain checksum 3154, 15 automatic collections, and a
65,520-byte arena high-water mark.

The standalone host regression also passed against both baseline and candidate:
306 exact-fit, split, and no-fit/fallback cases, covering every match position
in lists of lengths 0 through 16. It checks payload preservation, first-fit
selection, and heap integrity, with AddressSanitizer and UndefinedBehaviorSanitizer.

```sh
python3 tests/run_allocation_search_host.py
```

The host runner changes alignment only in a temporary runtime copy to accommodate
64-bit host headers, and stubs the platform context/panic hooks. Board timings
and managed-runtime checks use the unmodified production source and board ABI.
