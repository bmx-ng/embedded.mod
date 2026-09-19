# ESP32-S3 44-pin N16R8 collector benchmark — 2026-09-19

Board: ESP32-S3-WROOM-1-N16R8, revision v0.2, 16 MiB flash and 8 MiB PSRAM.
The managed arena was fixed at 64 KiB in internal SRAM. The ESP-IDF boot log
reported a 160 MHz CPU clock. `mark_queue=0` selects repeated heap scans and
`mark_queue=1` selects the mark queue. Both images include the execution-context
refactor and use the same benchmark source.

The board was flashed and verified for each variant. Run order was legacy,
queue, queue, legacy; the second run of each image used a UART reset. Each GC
case has 12 samples per run. The two runs of each variant agreed closely.

| Workload | Legacy median | Queue median | Speedup |
| --- | ---: | ---: | ---: |
| 120,000 rounds of ordinary field updates | 2,744,606 µs | 2,744,604 µs | 1.00× |
| Trace 96 live nodes, backward allocation order | 3,017 µs | 532.5–533 µs | 5.66–5.67× |
| Collect after allocating 32 unreachable nodes | 3,786 µs | 564 µs | 6.71× |

Both variants reported the same checksum (286270096) and managed arena high
water (6560 bytes). The queue ELF uses 28 fewer bytes of text (141,845 vs
141,873 bytes), with the same data (52,572 bytes) and BSS (369,465 bytes).

Raw logs: [legacy run 1](s3_legacy.txt),
[queue run 1](s3_queue.txt),
[queue run 2](s3_queue_repeat.txt),
[legacy run 2](s3_legacy_repeat.txt).

The ESP-IDF startup log describes a multicore app, but the benchmark ran
BlitzMax work only on CPU0. Managed work on CPU1 remains disabled pending the
GC rendezvous and allocation locking. These synthetic results do not predict
pause times for every application.
