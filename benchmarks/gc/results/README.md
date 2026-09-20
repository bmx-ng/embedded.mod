# Collector hardware checks

The [allocation-search results](allocation_results.md) compare one-pass
allocation search with the merged allocator on both boards.

The [linear sweep results](sweep_results.md) measure the next collector
improvements against the merged two-cursor implementation.

The [larger-heap scaling test](scale_results.md) compares the previous lookup
with two temporary cursors on Pico 2 W and ESP32-S3 hardware.

## Single-cursor lookup trial — 2026-09-20

The first lookup trial searched from its last matched block in address order and
rejects pointers outside the arena before looking at heap blocks. These
collector-only changes add no heap metadata. Both boards passed the varied
graph and heap checks, checksum 3154, and 15 automatic collections. The
ordinary-update timing in `gc_benchmark` was effectively unchanged.

| Collection case | Pico 2 W before | Pico 2 W after | ESP32-S3 before | ESP32-S3 after |
| --- | ---: | ---: | ---: | ---: |
| Forward chain | 340.5 µs | 163 µs | 371 µs | 212 µs |
| Wide shared graph | 580 µs | 167 µs | 663 µs | 212 µs |
| Mixed cycle | 176.5 µs | 98 µs | 205 µs | 120 µs |
| Backward chain | 536 µs | 189.5 µs | 532.5 µs | 228 µs |

Values are medians of 12 collection samples from 64 KiB SRAM heap builds.
The before figures for the first three cases are from the queue-only runs
below; the backward-chain figures are from the original queue runs in
[`history/`](../history/README.md). New raw captures:
[Pico varied](lookup_pico2w_varied.log),
[ESP32-S3 varied](lookup_s3_varied.log),
[Pico backward chain](lookup_pico2w_benchmark.log), and
[ESP32-S3 backward chain](lookup_s3_benchmark.log).

That cursor could still traverse much of the heap for references that jumped
between distant blocks. The two-cursor scaling test above addresses this
particular pattern with one extra temporary pointer.

## Queue-only baseline — 2026-09-19

The integrated collector was built without a marker selection switch and run
on a Pico 2 W and an ESP32-S3 44-pin N16R8, each with a 64 KiB SRAM managed
heap. The varied benchmark passed its graph and heap checks on both boards,
reported checksum 3154, and preserved a live graph through 15 automatic
collections. The arena high water was 65,520 bytes on each board.

| Collection case | Pico 2 W median | ESP32-S3 median |
| --- | ---: | ---: |
| Almost empty heap | 15 µs | 25 µs |
| Forward-linked chain | 340.5 µs | 371 µs |
| Wide shared graph | 580 µs | 663 µs |
| Mixed cycle | 176.5 µs | 205 µs |
| Reclaim mixed garbage | 152 µs | 202 µs |

[Pico raw capture](integrated_pico2w_varied.log) and
[ESP32-S3 raw capture](integrated_s3_varied.log). Run `summarize.py` from the
parent directory to validate and summarize them again. The historical A/B
comparisons are in [`history/`](../history/README.md).

The benchmark runs managed code only on core 0.
