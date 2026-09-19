# Queue-only hardware check — 2026-09-19

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
