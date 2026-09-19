# Pico 2 W collector benchmark — 2026-09-19

Board: Raspberry Pi Pico 2 W, RP2350 Arm secure target. Both release builds
used a 64 KiB managed arena and the same benchmark source. `mark_queue=0`
selects repeated heap scans; `mark_queue=1` selects the mark queue. Both
images include the execution-context refactor. This is a single-core managed
workload: the second core did not run BlitzMax code.

The board was flashed and verified for each run. The order was legacy, queue,
legacy, queue. Each GC case has 12 samples per run; values below are medians
and were identical across the two runs of each variant.

| Workload | Legacy median | Queue median | Speedup |
| --- | ---: | ---: | ---: |
| 120,000 rounds of ordinary field updates | 772,006–772,007 µs | 772,004–772,005 µs | 1.00× |
| Trace 96 live nodes, backward allocation order | 2,119 µs | 536 µs | 3.95× |
| Collect after allocating 32 unreachable nodes | 2,618 µs | 559 µs | 4.68× |

Both variants reported the same checksum (286270096) and managed arena high
water (6560 bytes). The compiled queue image uses 152 more bytes of firmware
text (52,768 vs 52,616 bytes) and the same BSS (69,064 bytes). It adds no
per-object storage or measured arena use for this workload.

Raw logs: [legacy run 1](pico2w_legacy.txt),
[queue run 1](pico2w_queue.txt),
[legacy run 2](pico2w_legacy_repeat.txt),
[queue run 2](pico2w_queue_repeat.txt).

These results measure this small, chain-heavy synthetic workload. They do not
establish the pause distribution or throughput of a larger application, and
they do not measure concurrent managed work on core 1.
